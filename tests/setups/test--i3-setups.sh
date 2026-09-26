#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# The i3 setups' guard branches, run on the host with a stubbed PATH:
#   - with neither XFCE nor LXQt, i3--setup.sh skips (exit 0) — that is what
#     makes the i3 template safe to select on any booth — and its three
#     extension setups skip too, since i3 was never set up;
#   - an unknown mod key fails the build instead of guessing, and it does so
#     before anything is installed.
# What the scripts write into a real XFCE / LXQt image is
# tests/complex/test-i3-desktops.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
BASH_BIN="$(command -v bash)"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/xfce"
LOG="$STUB/calls.log"
: > "$LOG"

# Only what the scripts need before their guards; no xfce4-session, startlxqt
# or i3 — whatever the host has installed.
for tool in basename dirname; do
    ln -s "$(command -v "$tool")" "$STUB/bin/$tool"
done
# Anything that would install or touch the system logs itself instead.
for tool in apt--install.sh apt-get dpkg-query; do
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$tool" "$LOG" > "$STUB/bin/$tool"
    chmod +x "$STUB/bin/$tool"
done
# A PATH with XFCE "installed" (for the mod-key case).
printf '#!/bin/bash\nexit 0\n' > "$STUB/xfce/xfce4-session"
chmod +x "$STUB/xfce/xfce4-session"

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

# ---- no desktop: every i3 setup skips, exit 0, nothing installed ----
for s in i3--setup.sh i3-default--setup.sh i3-ctrl-alt--setup.sh i3-gaps--setup.sh; do
    run "$STUB/bin" "$s"
    if [[ "$RC" -eq 0 ]] && grep -q "^SKIP: $s" <<< "$OUT"; then
        check "true"  "$s skips (exit 0) without XFCE/LXQt/i3"
    else
        check "false" "$s skips (exit 0) without XFCE/LXQt/i3" "rc=$RC out=$OUT"
    fi
done
if grep -q 'neither XFCE nor LXQt' <<< "$(env -i EUID=0 PATH="$STUB/bin" "$BASH_BIN" "$SETUPS/i3--setup.sh" 2>&1 < /dev/null || true)"; then
    check "true"  "i3--setup.sh says why it skipped"
else
    check "false" "i3--setup.sh says why it skipped"
fi
if [[ ! -s "$LOG" ]]; then
    check "true"  "Skipping installs nothing"
else
    check "false" "Skipping installs nothing" "calls: $(cat "$LOG")"
fi

# ---- unknown mod key: fail the build, before installing ----
: > "$LOG"
run "$STUB/xfce:$STUB/bin" i3--setup.sh hyper
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
