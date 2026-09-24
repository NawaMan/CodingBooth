#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: default-terminal on KDE (kitty+default)
#
# Two separate things have to point at Kitty:
#   - kdeglobals' General/TerminalApplication — Dolphin's "Open Terminal Here"
#     and System Settings' "Default Applications > Terminal Emulator".
#   - kglobalshortcutsrc's Ctrl+Alt+T, which is Konsole's own global shortcut
#     (X-KDE-Shortcuts in its .desktop) and ignores TerminalApplication.
# Proven live (a real Ctrl+Alt+T on a fresh booth launched kitty, not konsole);
# this test pins the files that made it so.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: default-terminal on KDE ==="

FAILED=0
KG='$HOME/.config/kdeglobals'
KS='$HOME/.config/kglobalshortcutsrc'
HOOK='bash /usr/share/startup.d/58-cb-default-terminal--startup.sh >/dev/null 2>&1 || true'

ACTUAL=$(run_coding_booth --silence-build -- "cat $KG; echo ---SHORTCUTS---; cat $KS" 2>/dev/null) || ACTUAL=""
KG_PART="${ACTUAL%%---SHORTCUTS---*}"
KS_PART="${ACTUAL#*---SHORTCUTS---}"

# Test 1: TerminalApplication points at kitty
if echo "$KG_PART" | grep -q '^TerminalApplication=kitty$'; then
    print_test_result "true" "$0" "1" "KDE's TerminalApplication points at kitty"
else
    print_test_result "false" "$0" "1" "KDE's TerminalApplication should point at kitty"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: Ctrl+Alt+T launches kitty.desktop, and Konsole no longer holds it
if echo "$KS_PART" | grep -A3 '^\[kitty\.desktop\]' | grep -q '^_launch=Ctrl+Alt+T,' \
   && echo "$KS_PART" | grep -A3 '^\[org\.kde\.konsole\.desktop\]' | grep -q '^_launch=none,'; then
    print_test_result "true" "$0" "2" "Ctrl+Alt+T moved from Konsole to kitty"
else
    print_test_result "false" "$0" "2" "Ctrl+Alt+T should move from Konsole to kitty"
    echo "  Actual output: ${KS_PART:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 3: a hand-set TerminalApplication, and Konsole's launch key rebound by
# hand, survive a later container start.
CMD="printf '[General]\nTerminalApplication=konsole\n' > $KG; printf '[org.kde.konsole.desktop]\n_launch=Meta+Return,Ctrl+Alt+T,Konsole\n' > $KS; $HOOK; cat $KG $KS"
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null) || ACTUAL=""

if echo "$ACTUAL" | grep -q '^TerminalApplication=konsole$' \
   && echo "$ACTUAL" | grep -q '^_launch=Meta+Return,' \
   && ! echo "$ACTUAL" | grep -q 'kitty'; then
    print_test_result "true" "$0" "3" "hand-set terminal and rebound Konsole shortcut are not overwritten"
else
    print_test_result "false" "$0" "3" "hand-set terminal and rebound Konsole shortcut should not be overwritten"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
