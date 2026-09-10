#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Wayland (labwc) foot Nerd Font (Fira Code)
#
# Builds a real booth with `setup wayland` and checks that foot's default font
# actually works: the Fira Code Nerd Font is installed and resolvable by
# fontconfig, and start-wayland seeds ~/.config/foot/foot.ini with it on first
# run, without clobbering a later user font change.
#
# wayland--setup.sh and fira-code-nerd-font--setup.sh are loaded from .booth/setups/
# (mirror variants/base/setups/) until the released base image ships the font.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Wayland (labwc) foot Nerd Font (Fira Code) ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

booth_first() {
    capture_codingbooth "head -1" --silence-build -- "$@"
}

# Test 1: booth starts and can run a trivial command
ACTUAL=$(booth_first echo wayland-font-ok) || ACTUAL=""
if [[ "$ACTUAL" == "wayland-font-ok" ]]; then
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

# Test 3: start-wayland seeds foot.ini with the Nerd Font on first run
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  nohup start-wayland >/tmp/sw.log 2>&1 &
  for _ in $(seq 1 20); do
    [ -f "$HOME/.config/foot/foot.ini" ] && break
    sleep 1
  done
  cat "$HOME/.config/foot/foot.ini" 2>&1
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^font=FiraCode Nerd Font Mono:size=11$'; then
    print_test_result "true" "$0" "3" "start-wayland seeds foot.ini with the Nerd Font"
else
    print_test_result "false" "$0" "3" "start-wayland should seed foot.ini with the Nerd Font"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: a pre-existing foot.ini (a user's own font choice) is left alone
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  mkdir -p "$HOME/.config/foot"
  printf "[main]\nfont=monospace:size=8\n" > "$HOME/.config/foot/foot.ini"
  nohup start-wayland >/tmp/sw.log 2>&1 &
  sleep 6
  cat "$HOME/.config/foot/foot.ini"
') || ACTUAL=""
if echo "$ACTUAL" | grep -q '^font=monospace:size=8$'; then
    print_test_result "true" "$0" "4" "an existing foot.ini is not overwritten"
else
    print_test_result "false" "$0" "4" "an existing foot.ini should not be overwritten"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
