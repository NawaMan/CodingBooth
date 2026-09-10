#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: KDE Konsole Nerd Font (Fira Code)
#
# Builds a real booth with `setup kde` and checks that Konsole's default font
# actually works: the Fira Code Nerd Font is installed and resolvable by
# fontconfig, and kde--setup.sh's seeded Shell.profile carries the Font= line
# on first run, without clobbering a later user font change.
#
# kde--setup.sh and fira-code-nerd-font--setup.sh are loaded from .booth/setups/
# (mirror variants/base/setups/) until the released base image ships the font.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: KDE Konsole Nerd Font (Fira Code) ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

booth_first() {
    capture_codingbooth "head -1" --silence-build -- "$@"
}

# Test 1: booth starts and can run a trivial command
ACTUAL=$(booth_first echo kde-font-ok) || ACTUAL=""
if [[ "$ACTUAL" == "kde-font-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts and runs a command"
else
    print_test_result "false" "$0" "1" "booth should start and run a command"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

# Test 2: fontconfig actually resolves the Nerd Font (not just a file on disk).
# Not the container's very first exec'd command: a leading statement avoids a
# cold-container fontconfig race (see the XFCE terminal font test for detail).
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'echo ready; fc-match "FiraCode Nerd Font Mono"') || ACTUAL=""
if echo "$ACTUAL" | grep -qi "FiraCodeNerdFontMono"; then
    print_test_result "true" "$0" "2" "fontconfig resolves FiraCode Nerd Font Mono"
else
    print_test_result "false" "$0" "2" "fontconfig should resolve FiraCode Nerd Font Mono"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: start-kde seeds Konsole's Shell.profile with the Nerd Font on first run
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  nohup start-kde >/tmp/sk.log 2>&1 &
  for _ in $(seq 1 20); do
    [ -f "$HOME/.local/share/konsole/Shell.profile" ] && break
    sleep 1
  done
  cat "$HOME/.local/share/konsole/Shell.profile" 2>&1
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^Font=FiraCode Nerd Font Mono,11,'; then
    print_test_result "true" "$0" "3" "start-kde seeds Shell.profile with the Nerd Font"
else
    print_test_result "false" "$0" "3" "start-kde should seed Shell.profile with the Nerd Font"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: a pre-existing Shell.profile (a user's own font choice) is left alone
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  mkdir -p "$HOME/.local/share/konsole"
  printf "[General]\nCommand=/bin/bash\nName=Shell\n\n[Appearance]\nFont=Monospace,12,-1,5,50,0,0,0,0,0\n" > "$HOME/.local/share/konsole/Shell.profile"
  nohup start-kde >/tmp/sk.log 2>&1 &
  sleep 6
  cat "$HOME/.local/share/konsole/Shell.profile"
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^Font=Monospace,12,'; then
    print_test_result "true" "$0" "4" "an existing Shell.profile is not overwritten"
else
    print_test_result "false" "$0" "4" "an existing Shell.profile should not be overwritten"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
