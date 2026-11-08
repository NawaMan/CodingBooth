#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Run the booth once per profile selection and check what reached the container:
#   none            -> base + default
#   prod            -> base + prod                 (default steps aside)
#   default,prod    -> base + default + prod       (prod wins scalars and env files)
#   prod,default    -> base + prod + default       (now default wins: order matters)
#   BOOTH_PROFILES  -> same as --profile
#
# --profile is read on the host, so this is an on-host test: each case is its own
# one-shot `booth -- <cmd>`. No --port here -- a CLI --port beats every profile
# and would hide the `port` scalar this test checks.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)" || { echo "no booth found under $REPO_ROOT" >&2; exit 1; }

cd "$(dirname "$0")/.."

export CB_BROWSER=false
unset BOOTH_PROFILES

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

CONTAINER_NAME="profiles-example-test"

# The env files are gitignored, so a fresh clone has none. Write the samples, and
# on exit remove only those this test wrote -- a user's own are left alone.
created_env_files=()
for f in .booth/.env .booth/.default--env .booth/.prod--env; do
    [[ -e "$f" ]] || created_env_files+=("$f")
done

cleanup() {
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    for f in ${created_env_files[@]+"${created_env_files[@]}"}; do
        rm -f "$f"
    done
}
trap cleanup EXIT

./scripts/write-env-files.sh >/dev/null
# The samples must be what the expectations below assume.
for pair in .booth/.env:base .booth/.default--env:default .booth/.prod--env:prod; do
    f="${pair%%:*}"
    grep -qx "LEVEL=${pair#*:}" "$f" || fail "$f does not hold LEVEL=${pair#*:} -- move it aside to run this test"
done

# show <label> [booth args...] : run the probe, keep its KEY=value lines in $OUT.
show() {
    local label="$1"; shift
    echo
    echo "=== $label ==="
    OUT="$("$BOOTH" "$@" --name "$CONTAINER_NAME" -- ./scripts/show-profile.sh 2>&1 | tr -d '\r' \
            | grep -E '^(PORT|BASE_ONLY|DEFAULT_ONLY|PROD_ONLY|LEVEL)=' || true)"
    echo "$OUT"
    [[ -n "$OUT" ]] || fail "$label: the probe printed nothing"
}

# expect <KEY> <value> : value "" means unset.
expect() {
    local key="$1" want="$2" got
    got="$(grep "^$key=" <<< "$OUT" | head -1 | cut -d= -f2-)"
    if [[ "$got" == "$want" ]]; then
        pass "$key=${want:-(unset)}"
    else
        fail "$key: expected '${want:-(unset)}', got '${got:-(unset)}'"
    fi
}

echo "=== Testing profiles-example ==="
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

show "no selection: default applies"
expect PORT         50912
expect BASE_ONLY    yes
expect DEFAULT_ONLY yes
expect PROD_ONLY    ""
expect LEVEL        default

show "--profile prod: default steps aside" --profile prod
expect PORT         50913
expect BASE_ONLY    yes
expect DEFAULT_ONLY ""
expect PROD_ONLY    yes
expect LEVEL        prod

show "--profile default,prod: both, prod applied last" --profile default,prod
expect PORT         50913     # scalar: the later profile wins
expect BASE_ONLY    yes       # run-args: lists add up across all layers
expect DEFAULT_ONLY yes
expect PROD_ONLY    yes
expect LEVEL        prod      # env files: the later profile's wins

show "--profile prod,default: both, default applied last" --profile prod,default
expect PORT         50912
expect BASE_ONLY    yes
expect DEFAULT_ONLY yes
expect PROD_ONLY    yes
expect LEVEL        default

BOOTH_PROFILES=prod show "BOOTH_PROFILES=prod: same as --profile prod"
expect PORT         50913
expect DEFAULT_ONLY ""
expect PROD_ONLY    yes
expect LEVEL        prod

echo
echo -e "${GREEN}All tests passed!${NC}"
