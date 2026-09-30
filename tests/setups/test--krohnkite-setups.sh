#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# The Krohnkite setups' guard branches, run on the host with a stubbed PATH:
#   - without KDE Plasma 6, krohnkite--setup.sh skips (exit 0) — that is what
#     makes the krohnkite template safe to select on any booth — and its two
#     extension setups skip too, since Krohnkite was never set up;
#   - an unknown mod key fails the build instead of guessing, and it does so
#     before anything is downloaded or installed;
#   - a --version other than the pinned one needs its --sha256;
#   - the deprecated bismuth setups run their Krohnkite equivalents, saying so.
# What the scripts write into a real KDE image is tests/complex/test-krohnkite-kde.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"
BASH_BIN="$(command -v bash)"

STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/kde"
LOG="$STUB/calls.log"
: > "$LOG"

# Only what the scripts need before their guards; no kwin_x11 or kwriteconfig6
# — whatever the host has installed.
for tool in basename dirname; do
    ln -s "$(command -v "$tool")" "$STUB/bin/$tool"
done
# Anything that would install or touch the system logs itself instead.
for tool in apt--install.sh apt-get dpkg-query curl unzip; do
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n' "$tool" "$LOG" > "$STUB/bin/$tool"
    chmod +x "$STUB/bin/$tool"
done
# A PATH with KDE Plasma 6 "installed" (for the mod-key and version cases).
for tool in kwin_x11 kwriteconfig6; do
    printf '#!/bin/bash\nexit 0\n' > "$STUB/kde/$tool"
    chmod +x "$STUB/kde/$tool"
done

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

# ---- no KDE: every Krohnkite setup skips, exit 0, nothing installed ----
for s in krohnkite--setup.sh krohnkite-default--setup.sh krohnkite-gaps--setup.sh; do
    run "$STUB/bin" "$s"
    if [[ "$RC" -eq 0 ]] && grep -q "^SKIP: $s" <<< "$OUT"; then
        check "true"  "$s skips (exit 0) without KDE/Krohnkite"
    else
        check "false" "$s skips (exit 0) without KDE/Krohnkite" "rc=$RC out=$OUT"
    fi
done
run "$STUB/bin" krohnkite--setup.sh
if grep -q 'KDE Plasma 6 is not installed' <<< "$OUT"; then
    check "true"  "krohnkite--setup.sh says why it skipped"
else
    check "false" "krohnkite--setup.sh says why it skipped" "out=$OUT"
fi
if [[ ! -s "$LOG" ]]; then
    check "true"  "Skipping installs nothing"
else
    check "false" "Skipping installs nothing" "calls: $(cat "$LOG")"
fi

# ---- unknown mod key: fail the build, before downloading or installing ----
: > "$LOG"
run "$STUB/kde:$STUB/bin" krohnkite--setup.sh hyper
if [[ "$RC" -ne 0 ]] && grep -q "Unknown mod key 'hyper'" <<< "$OUT"; then
    check "true"  "An unknown mod key fails the build with an explanation"
else
    check "false" "An unknown mod key fails the build with an explanation" "rc=$RC out=$OUT"
fi
if [[ ! -s "$LOG" ]]; then
    check "true"  "…and nothing was downloaded or installed first"
else
    check "false" "…and nothing was downloaded or installed first" "calls: $(cat "$LOG")"
fi

# ---- an unpinned version needs its checksum ----
: > "$LOG"
run "$STUB/kde:$STUB/bin" krohnkite--setup.sh --version 0.9.9.1
if [[ "$RC" -ne 0 ]] && grep -q -- "--version 0.9.9.1 needs --sha256" <<< "$OUT" && [[ ! -s "$LOG" ]]; then
    check "true"  "--version without --sha256 fails before downloading"
else
    check "false" "--version without --sha256 fails before downloading" "rc=$RC out=$OUT calls: $(cat "$LOG")"
fi

# ---- deprecated bismuth setups: run the Krohnkite ones, with a notice ----
for pair in bismuth:krohnkite bismuth-default:krohnkite-default bismuth-gaps:krohnkite-gaps; do
    old="${pair%%:*}--setup.sh" new="${pair##*:}--setup.sh"
    run "$STUB/bin" "$old"
    if [[ "$RC" -eq 0 ]] && grep -q "$old is deprecated" <<< "$OUT" && grep -q "^SKIP: $new" <<< "$OUT"; then
        check "true"  "$old is a shim for $new"
    else
        check "false" "$old is a shim for $new" "rc=$RC out=$OUT"
    fi
done
run "$STUB/kde:$STUB/bin" bismuth--setup.sh hyper
if [[ "$RC" -ne 0 ]] && grep -q "Unknown mod key 'hyper'" <<< "$OUT"; then
    check "true"  "bismuth--setup.sh passes its arguments through"
else
    check "false" "bismuth--setup.sh passes its arguments through" "rc=$RC out=$OUT"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
