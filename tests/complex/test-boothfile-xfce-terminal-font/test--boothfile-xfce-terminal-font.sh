#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: XFCE terminal Nerd Font (Fira Code)
#
# Builds a real booth with `setup xfce` and checks that xfce4-terminal's
# default font actually works: the Fira Code Nerd Font is installed and
# resolvable by fontconfig, start-xfce seeds ~/.config/xfce4/terminal/terminalrc
# with it on first run, and a later user font change is never overwritten on
# a subsequent run.
#
# xfce--setup.sh is loaded from .booth/setups/ (mirrors
# variants/base/setups/xfce--setup.sh) until the released base image ships
# the font install.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: XFCE terminal Nerd Font (Fira Code) ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

booth_first() {
    capture_codingbooth "head -1" --silence-build -- "$@"
}

# Test 1: booth starts and can run a trivial command
ACTUAL=$(booth_first echo xfce-font-ok) || ACTUAL=""
if [[ "$ACTUAL" == "xfce-font-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts and runs a command"
else
    print_test_result "false" "$0" "1" "booth should start and run a command"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

# Test 2: fontconfig actually resolves the Nerd Font (not just a file on disk).
# fc-match must not be the container's very first exec'd command: cold-container
# timing races fontconfig's cache check against something still initializing, so
# a harmless leading statement (as any real shell session would have) avoids it.
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'echo ready; fc-match "FiraCode Nerd Font Mono"') || ACTUAL=""
if echo "$ACTUAL" | grep -qi "FiraCodeNerdFontMono"; then
    print_test_result "true" "$0" "2" "fontconfig resolves FiraCode Nerd Font Mono"
else
    print_test_result "false" "$0" "2" "fontconfig should resolve FiraCode Nerd Font Mono"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: start-xfce seeds xfce4-terminal's default font on first run
ACTUAL=$(capture_codingbooth "cat" --silence-build -- bash -c '
  nohup start-xfce >/tmp/sx.log 2>&1 &
  for _ in $(seq 1 20); do
    [ -f "$HOME/.config/xfce4/terminal/terminalrc" ] && break
    sleep 1
  done
  cat "$HOME/.config/xfce4/terminal/terminalrc" 2>&1
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^FontName=FiraCode Nerd Font Mono 11$'; then
    print_test_result "true" "$0" "3" "start-xfce seeds terminalrc with the Nerd Font"
else
    print_test_result "false" "$0" "3" "start-xfce should seed terminalrc with the Nerd Font"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: a pre-existing terminalrc (a user's own font choice) is left alone
ACTUAL=$(capture_codingbooth "cat" --silence-build -- bash -c '
  mkdir -p "$HOME/.config/xfce4/terminal"
  printf "[Configuration]\nFontName=Monospace 12\n" > "$HOME/.config/xfce4/terminal/terminalrc"
  nohup start-xfce >/tmp/sx.log 2>&1 &
  sleep 5
  cat "$HOME/.config/xfce4/terminal/terminalrc"
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^FontName=Monospace 12$'; then
    print_test_result "true" "$0" "4" "an existing terminalrc is not overwritten"
else
    print_test_result "false" "$0" "4" "an existing terminalrc should not be overwritten"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
