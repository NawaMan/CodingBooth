#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: default-terminal on XFCE (alacritty+default)
#
# Selecting "alacritty+default" should make Alacritty the DE's own default
# terminal, not just an extra app in the menu — checked by reading back the
# same file XFCE's Preferred Applications settings dialog writes to.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: default-terminal on XFCE ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- "cat \$HOME/.config/xfce4/helpers.rc" 2>/dev/null)

if echo "$ACTUAL" | grep -q '^TerminalEmulator=alacritty$'; then
    print_test_result "true" "$0" "1" "XFCE's TerminalEmulator points at alacritty"
else
    print_test_result "false" "$0" "1" "XFCE's TerminalEmulator should point at alacritty"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# A hand-edited helpers.rc (the user picking a different terminal afterwards,
# or a second container start) must never be clobbered by the startup hook.
CMD='mkdir -p $HOME/.config/xfce4; printf "TerminalEmulator=xfce4-terminal\n" > $HOME/.config/xfce4/helpers.rc; bash /usr/share/startup.d/58-cb-default-terminal--startup.sh >/dev/null 2>&1 || true; cat $HOME/.config/xfce4/helpers.rc'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q '^TerminalEmulator=xfce4-terminal$'; then
    print_test_result "true" "$0" "2" "a hand-edited helpers.rc is not overwritten"
else
    print_test_result "false" "$0" "2" "a hand-edited helpers.rc should not be overwritten"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Debian's generic x-terminal-emulator points at alacritty, not xfce4-terminal
ACTUAL=$(run_coding_booth --silence-build -- "readlink -f /usr/bin/x-terminal-emulator" 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == "/usr/bin/alacritty" ]]; then
    print_test_result "true" "$0" "3" "x-terminal-emulator points at alacritty"
else
    print_test_result "false" "$0" "3" "x-terminal-emulator should point at alacritty"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
