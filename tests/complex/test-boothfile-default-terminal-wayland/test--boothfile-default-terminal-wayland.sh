#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: default-terminal on labwc/Wayland (kitty+default)
#
# labwc has no DE-level "default terminal" registry — the terminal is
# hardcoded into start-wayland's runtime-generated autostart and menu.xml.
# "kitty+default" exports $DEFAULT_TERMINAL (read by wayland--setup.sh's
# ${DEFAULT_TERMINAL:-foot}), so this starts start-wayland for real and reads
# back the files it generates, the same way test-boothfile-wayland-terminal-font
# proves the font seed.
#
# start-wayland is launched with a scrubbed, non-login environment on purpose:
# the real desktop runs it via booth-entry's `runuser -u coder -- start-wayland-wrapped`,
# which never sources /etc/profile.d. An earlier version passed $DEFAULT_TERMINAL
# through profile.d, passed this test from a login shell, and still came up with
# foot on a real booth.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: default-terminal on labwc/Wayland ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# Test 1: start-wayland's autostart runs kitty instead of foot
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  env -i HOME="$HOME" USER="$USER" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    nohup start-wayland >/tmp/sw.log 2>&1 &
  for _ in $(seq 1 20); do
    [ -f "$HOME/.config/labwc/autostart" ] && break
    sleep 1
  done
  cat "$HOME/.config/labwc/autostart" 2>&1
') || ACTUAL=""

if echo "$ACTUAL" | grep -q '^kitty &$'; then
    print_test_result "true" "$0" "1" "labwc autostart launches kitty instead of foot"
else
    print_test_result "false" "$0" "1" "labwc autostart should launch kitty instead of foot"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: the right-click "Terminal" menu entry runs kitty instead of foot
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  env -i HOME="$HOME" USER="$USER" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    nohup start-wayland >/tmp/sw.log 2>&1 &
  for _ in $(seq 1 20); do
    [ -f "$HOME/.config/labwc/menu.xml" ] && break
    sleep 1
  done
  grep -i "Terminal" "$HOME/.config/labwc/menu.xml" 2>&1
') || ACTUAL=""

if echo "$ACTUAL" | grep -q '<command>kitty</command>'; then
    print_test_result "true" "$0" "2" "labwc's right-click Terminal menu entry runs kitty"
else
    print_test_result "false" "$0" "2" "labwc's right-click Terminal menu entry should run kitty"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: Super+Enter (labwc's built-in terminal key, hardcoded to alacritty)
# is rebound to kitty, and the generated rc.xml keeps labwc's other defaults.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- '
  env -i HOME="$HOME" USER="$USER" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    nohup start-wayland >/tmp/sw.log 2>&1 &
  for _ in $(seq 1 20); do
    [ -f "$HOME/.config/labwc/rc.xml" ] && break
    sleep 1
  done
  cat "$HOME/.config/labwc/rc.xml" 2>&1
') || ACTUAL=""

if echo "$ACTUAL" | grep -q '<keybind key="W-Return"><action name="Execute" command="kitty" />' \
   && echo "$ACTUAL" | grep -q '<default />'; then
    print_test_result "true" "$0" "3" "Super+Enter runs kitty, labwc's default keybinds kept"
else
    print_test_result "false" "$0" "3" "Super+Enter should run kitty, keeping labwc's default keybinds"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: Debian's generic x-terminal-emulator points at kitty, not foot
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'readlink -f /usr/bin/x-terminal-emulator') || ACTUAL=""

if [[ "$ACTUAL" == "/usr/bin/kitty" ]]; then
    print_test_result "true" "$0" "4" "x-terminal-emulator points at kitty"
else
    print_test_result "false" "$0" "4" "x-terminal-emulator should point at kitty"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
