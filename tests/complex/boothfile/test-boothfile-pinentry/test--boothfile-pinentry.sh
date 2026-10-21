#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: pinentry on XFCE (setup pinentry --flavor auto)
#
# auto should pick pinentry-gtk2 on XFCE and make it gpg's pinentry, so a
# passphrase prompt (folio, pass, gpg) opens as a dialog on the desktop.
# `GETINFO flavor` asks the pinentry gpg-agent would run what it is: with a
# display it is gtk2; without one (a Console UI tab) it must fall back to
# curses, or a terminal-only prompt would fail outright.
#
# The dialog itself needs the running desktop, which a command-mode booth does
# not start; it was checked by hand on XFCE, KDE and Wayland.
#
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: pinentry on XFCE ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- "readlink -f /usr/bin/pinentry" 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == "/usr/bin/pinentry-gtk-2" ]]; then
    print_test_result "true" "$0" "1" "pinentry points at pinentry-gtk-2 on XFCE"
else
    print_test_result "false" "$0" "1" "pinentry should point at pinentry-gtk-2 on XFCE"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

CMD='printf "GETINFO flavor\nBYE\n" | env -u DISPLAY -u WAYLAND_DISPLAY pinentry | grep "^D "'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == "D gtk2:curses" ]]; then
    print_test_result "true" "$0" "2" "with no display the gtk2 pinentry falls back to curses"
else
    print_test_result "false" "$0" "2" "with no display the gtk2 pinentry should fall back to curses"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
