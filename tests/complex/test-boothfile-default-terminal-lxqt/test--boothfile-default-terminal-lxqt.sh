#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: default-terminal on LXQt (alacritty+default)
#
# LXQt has no session-wide "default terminal" key that anything here reads
# (an earlier version wrote lxqt.conf's terminal=, which nothing consumed —
# PCManFM-Qt still launched xterm). What actually matters:
#   - PCManFM-Qt's [System] Terminal=, used by the desktop right-click and the
#     file manager's "Open in Terminal". PCManFM-Qt reads the user file OR the
#     /etc/xdg copy, never a merge, so the seed must keep the wallpaper keys.
#   - lxqt-globalkeysd's Ctrl+Alt+T, otherwise unbound in this image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: default-terminal on LXQt ==="

FAILED=0
PCM='$HOME/.config/pcmanfm-qt/lxqt/settings.conf'
KEYS='$HOME/.config/lxqt/globalkeyshortcuts.conf'
HOOK='bash /usr/share/startup.d/58-cb-default-terminal--startup.sh >/dev/null 2>&1 || true'

ACTUAL=$(run_coding_booth --silence-build -- "cat $PCM; echo ---KEYS---; cat $KEYS" 2>/dev/null) || ACTUAL=""
PCM_PART="${ACTUAL%%---KEYS---*}"
KEYS_PART="${ACTUAL#*---KEYS---}"

# Test 1: PCManFM-Qt launches alacritty
if echo "$PCM_PART" | grep -q '^Terminal=alacritty$'; then
    print_test_result "true" "$0" "1" "PCManFM-Qt's Terminal points at alacritty"
else
    print_test_result "false" "$0" "1" "PCManFM-Qt's Terminal should point at alacritty"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: seeding the user file kept the system file's wallpaper settings
if echo "$PCM_PART" | grep -q '^Wallpaper=/usr/share/backgrounds/codingbooth/'; then
    print_test_result "true" "$0" "2" "the seeded settings.conf keeps the desktop wallpaper"
else
    print_test_result "false" "$0" "2" "the seeded settings.conf should keep the desktop wallpaper"
    echo "  Actual output: ${PCM_PART:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 3: Ctrl+Alt+T is bound to alacritty
if echo "$KEYS_PART" | grep -A3 '^\[Control%2BAlt%2BT\.' | grep -q '^Exec=alacritty$'; then
    print_test_result "true" "$0" "3" "Ctrl+Alt+T is bound to alacritty"
else
    print_test_result "false" "$0" "3" "Ctrl+Alt+T should be bound to alacritty"
    echo "  Actual output: ${KEYS_PART:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 4: a user's own choices survive a later container start — a terminal
# picked in PCManFM-Qt's preferences, and a Ctrl+Alt+T they rebound.
CMD="printf '[System]\nTerminal=qterminal\n' > $PCM; printf '[Control%%2BAlt%%2BT.9]\nEnabled=true\nExec=qterminal\n' > $KEYS; $HOOK; cat $PCM $KEYS"
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null) || ACTUAL=""

if echo "$ACTUAL" | grep -q '^Terminal=qterminal$' && ! echo "$ACTUAL" | grep -q 'alacritty'; then
    print_test_result "true" "$0" "4" "hand-set terminal and Ctrl+Alt+T are not overwritten"
else
    print_test_result "false" "$0" "4" "hand-set terminal and Ctrl+Alt+T should not be overwritten"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 5: PCManFM-Qt's own auto-saved fallback (Terminal=xterm, which is not
# installed) is not a user choice and gets replaced.
CMD="sed -i 's/^Terminal=.*/Terminal=xterm/' $PCM; $HOOK; grep '^Terminal=' $PCM"
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null) || ACTUAL=""

if echo "$ACTUAL" | grep -q '^Terminal=alacritty$'; then
    print_test_result "true" "$0" "5" "PCManFM-Qt's auto-saved Terminal=xterm is replaced"
else
    print_test_result "false" "$0" "5" "PCManFM-Qt's auto-saved Terminal=xterm should be replaced"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
