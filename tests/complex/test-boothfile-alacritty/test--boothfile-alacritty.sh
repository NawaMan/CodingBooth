#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Alacritty Installation
#
# Alacritty is GPU-accelerated (OpenGL) and normally needs a desktop session,
# but a booth's desktop has no host GPU either — it renders headless through
# Mesa's llvmpipe software rasterizer. This test proves that actually works:
# it starts a throwaway Xvnc session inside the container and launches
# Alacritty against it, rather than only checking the binary is on PATH.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Alacritty Installation ==="

FAILED=0

# Test 1: alacritty is on PATH and reports a version
ACTUAL=$(run_coding_booth --silence-build -- "alacritty --version" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" =~ ^alacritty\  ]]; then
    print_test_result "true" "$0" "1" "Alacritty is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Alacritty should be installed"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: it actually runs — start a throwaway Xvnc, launch Alacritty against
# it, and have the shell it opens write a marker file. Alacritty renders that
# shell in its own pty/window rather than the outer shell's stdout (so its own
# exit code doesn't reflect the child's either), so a file the child wrote is
# the only reliable way to observe what happened inside it.
CMD='Xvnc :1 -geometry 1280x800 -localhost yes -SecurityTypes=None >/tmp/xvnc.log 2>&1 & sleep 2; DISPLAY=:1 timeout 10 alacritty -e sh -c "echo ALACRITTY_RAN_OK > /tmp/alacritty-marker.txt"; sleep 1; cat /tmp/alacritty-marker.txt 2>/dev/null'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q "ALACRITTY_RAN_OK"; then
    print_test_result "true" "$0" "2" "Alacritty launches and runs a command under Xvnc"
else
    print_test_result "false" "$0" "2" "Alacritty should launch and run a command under Xvnc"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 3: it registers a desktop icon (via cb-desktop-icon.sh, seeded into
# /etc/skel/Desktop) — without this, a user has no way to discover it besides
# already knowing the command name.
ACTUAL=$(run_coding_booth --silence-build -- "ls /etc/skel/Desktop/*lacritty*.desktop" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == *"Alacritty.desktop" ]]; then
    print_test_result "true" "$0" "3" "Alacritty registers a desktop icon"
else
    print_test_result "false" "$0" "3" "Alacritty should register a desktop icon"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
