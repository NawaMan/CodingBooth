#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# The sway setups' guard branches, run on the host with a stubbed PATH:
#   - without the Wayland desktop (start-wayland), sway--setup.sh skips (exit 0)
#     — that is what makes the sway template safe to select on any booth — and
#     its two extension setups skip too, since sway was never set up;
#   - an unknown mod key fails the build instead of guessing, and it does so
#     before anything is installed.
# What the scripts write into a real Wayland image, and that start-wayland then
# runs sway, is tests/complex/test-sway-wayland.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
BASH_BIN="$(command -v bash)"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/wayland"
LOG="$STUB/calls.log"
: > "$LOG"

# Only what the scripts need before their guards; no start-wayland or sway —
# whatever the host has installed.
for tool in basename dirname; do
    ln -s "$(command -v "$tool")" "$STUB/bin/$tool"
done
# Anything that would install or touch the system logs itself instead.
for tool in apt--install.sh apt-get dpkg-query; do
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$tool" "$LOG" > "$STUB/bin/$tool"
    chmod +x "$STUB/bin/$tool"
done
# A PATH with the Wayland desktop "installed" (for the mod-key case).
printf '#!/bin/bash\nexit 0\n' > "$STUB/wayland/start-wayland"
chmod +x "$STUB/wayland/start-wayland"

FAILED=0
NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    NUM=$((NUM + 1))
    print_test_result "$ok" "$0" "$NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/          /'
        FAILED=$((FAILED + 1))
    fi
}

# run <path> <script> [args…] — sets OUT and RC; no TTY, as in a Docker build.
run() {
    local path="$1"; shift
    OUT=$(env -i EUID=0 HOME="$STUB" PATH="$path" "$BASH_BIN" "$SETUPS/$1" "${@:2}" 2>&1 < /dev/null) && RC=0 || RC=$?
}

# ---- no Wayland desktop: every sway setup skips, exit 0, nothing installed ----
for s in sway--setup.sh sway-ctrl-alt--setup.sh sway-gaps--setup.sh; do
    run "$STUB/bin" "$s"
    if [[ "$RC" -eq 0 ]] && grep -q "^SKIP: $s" <<< "$OUT"; then
        check "true"  "$s skips (exit 0) without the Wayland desktop/sway"
    else
        check "false" "$s skips (exit 0) without the Wayland desktop/sway" "rc=$RC out=$OUT"
    fi
done
run "$STUB/bin" sway--setup.sh
if grep -q 'the Wayland desktop is not installed' <<< "$OUT"; then
    check "true"  "sway--setup.sh says why it skipped"
else
    check "false" "sway--setup.sh says why it skipped" "out=$OUT"
fi
if [[ ! -s "$LOG" ]]; then
    check "true"  "Skipping installs nothing"
else
    check "false" "Skipping installs nothing" "calls: $(cat "$LOG")"
fi

# ---- unknown mod key: fail the build, before installing ----
: > "$LOG"
run "$STUB/wayland:$STUB/bin" sway--setup.sh hyper
if [[ "$RC" -ne 0 ]] && grep -q "Unknown mod key 'hyper'" <<< "$OUT"; then
    check "true"  "An unknown mod key fails the build with an explanation"
else
    check "false" "An unknown mod key fails the build with an explanation" "rc=$RC out=$OUT"
fi
if [[ ! -s "$LOG" ]]; then
    check "true"  "…and nothing was installed first"
else
    check "false" "…and nothing was installed first" "calls: $(cat "$LOG")"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
