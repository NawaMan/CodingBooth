#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: dind startup drops host-only docker credential helpers
#
# Extracts the startup script embedded in dind--setup.sh and asserts it:
#   - removes a credsStore whose docker-credential-* binary is absent
#     (Docker Desktop's "desktop"), keeping auths and other keys
#   - removes only the unresolvable credHelpers entries
#   - leaves a config alone when every helper resolves
#   - no-ops when there is no config
# No Docker / image build — hermetic host-side check (needs jq, like the image).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/variants/base/setups/dind--setup.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed on this host"
  exit 0
fi

STARTUP_BODY=$(awk "
  /^cat > \"\\\$\\{STARTUP_FILE\\}\" <<'STARTUP'\$/ { grab=1; next }
  grab && /^STARTUP\$/ { exit }
  grab { print }
" "$SETUP")

if [[ -z "$STARTUP_BODY" ]]; then
  echo "FAIL: could not extract STARTUP body from dind--setup.sh"
  exit 1
fi

# A dev host running this test can have real docker-credential-* binaries on
# PATH (Docker Desktop, gcloud CLI, ...). Passing $PATH through unfiltered
# would let the startup script find those, "resolve" the helper, and no-op —
# masking the "missing" case every run_case below means to simulate. Rather
# than filter PATH directory-by-directory (that can hide unrelated tools that
# happen to share a bin dir with a credential helper, like bash itself),
# symlink only the specific externals the startup script and this harness
# need into an isolated dir and use that as the entire non-stub PATH.
SAFE_BIN=$(mktemp -d)
trap "rm -rf '$SAFE_BIN'" EXIT
for tool in bash jq mv rm; do
  real=$(command -v "$tool") || { echo "FAIL: '$tool' not found on PATH" >&2; exit 1; }
  ln -s "$real" "$SAFE_BIN/$tool"
done
SAFE_PATH="$SAFE_BIN"

FAILED=0

# run_case NAME INPUT_JSON EXPECTED_JSON [helper names to stub on PATH...]
run_case() {
  local name="$1" input="$2" expected="$3"
  shift 3

  local work
  work=$(mktemp -d)
  mkdir -p "$work/home/.docker" "$work/bin"
  printf '%s\n' "$STARTUP_BODY" >"$work/startup.sh"
  [[ -n "$input" ]] && printf '%s\n' "$input" >"$work/home/.docker/config.json"
  for helper in "$@"; do
    printf '#!/bin/sh\n' >"$work/bin/docker-credential-$helper"
    chmod +x "$work/bin/docker-credential-$helper"
  done

  if ! HOME="$work/home" PATH="$work/bin:$SAFE_PATH" DOCKER_CONFIG= bash "$work/startup.sh" >/dev/null; then
    echo "FAIL: $name — startup exited non-zero"
    FAILED=$((FAILED + 1))
    rm -rf "$work"
    return
  fi

  if [[ -z "$input" ]]; then
    if [[ -e "$work/home/.docker/config.json" ]]; then
      echo "FAIL: $name — config should not have been created"
      FAILED=$((FAILED + 1))
    else
      echo "OK: $name"
    fi
    rm -rf "$work"
    return
  fi

  local got want
  got=$(jq -S . "$work/home/.docker/config.json")
  want=$(jq -S . <<<"$expected")
  if [[ "$got" == "$want" ]]; then
    echo "OK: $name"
  else
    echo "FAIL: $name"
    echo "  want: $want"
    echo "  got:  $got"
    FAILED=$((FAILED + 1))
  fi
  rm -rf "$work"
}

run_case "Docker Desktop credsStore removed" \
  '{"auths":{},"credsStore":"desktop","currentContext":"desktop-linux"}' \
  '{"auths":{},"currentContext":"desktop-linux"}'

run_case "auths kept when credsStore removed" \
  '{"auths":{"ghcr.io":{"auth":"abc"}},"credsStore":"desktop"}' \
  '{"auths":{"ghcr.io":{"auth":"abc"}}}'

run_case "only unresolvable credHelpers removed" \
  '{"credHelpers":{"gcr.io":"gcloud","ecr.example":"ecr-login"}}' \
  '{"credHelpers":{"gcr.io":"gcloud"}}' \
  gcloud

run_case "empty credHelpers dropped" \
  '{"credsStore":"osxkeychain","credHelpers":{"gcr.io":"gcloud"}}' \
  '{}'

run_case "resolvable helpers left alone" \
  '{"credsStore":"pass","credHelpers":{"gcr.io":"gcloud"}}' \
  '{"credsStore":"pass","credHelpers":{"gcr.io":"gcloud"}}' \
  pass gcloud

run_case "no config is a no-op" "" ""

if [[ "$FAILED" -eq 0 ]]; then
  echo "All dind docker-config helper checks passed."
  exit 0
fi
echo "$FAILED dind docker-config helper check(s) failed."
exit 1
