#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Ghostty Installation (+fancy)
#
# Ghostty is GTK4 + OpenGL and a booth's desktop has no host GPU — it renders
# headless through Mesa's llvmpipe. This test proves that actually works: it
# starts a throwaway Xvnc session inside the container and launches Ghostty
# against it, rather than only checking the binary is on PATH. It also checks
# the +fancy config is seeded into the user's home, is accepted by Ghostty
# itself, and that its JetBrains Mono Nerd Font is the font Ghostty loads.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Ghostty Installation ==="

FAILED=0

# Test 1: it is the pinned build — `ghostty --version` prints "Ghostty 1.3.1"
# for the .deb 1.3.1-0.ppa2.
EXPECTED_VERSION=$(sed -n 's/^GHOSTTY_VERSION="\([^-]*\)-.*"$/\1/p' .booth/setups/ghostty--setup.sh)
ACTUAL=$(run_coding_booth --silence-build -- "ghostty --version | head -1" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == "Ghostty ${EXPECTED_VERSION}" ]]; then
    print_test_result "true" "$0" "1" "Ghostty ${EXPECTED_VERSION} is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Ghostty ${EXPECTED_VERSION} should be installed"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: it actually runs — start a throwaway Xvnc, launch Ghostty against it,
# and have the shell it opens write a marker file. Ghostty renders that shell
# in its own pty/window, so a file the child wrote is the only reliable way to
# observe what happened inside it. --gtk-single-instance=false keeps it from
# handing the command to some other instance over D-Bus.
CMD='Xvnc :1 -geometry 1280x800 -localhost yes -SecurityTypes=None >/tmp/xvnc.log 2>&1 & sleep 2; DISPLAY=:1 timeout 15 ghostty --gtk-single-instance=false -e sh -c "echo GHOSTTY_RAN_OK > /tmp/ghostty-marker.txt; sleep 1" >/tmp/ghostty.log 2>&1; cat /tmp/ghostty-marker.txt 2>/dev/null; grep -o "font regular: .*" /tmp/ghostty.log | head -1'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q "GHOSTTY_RAN_OK"; then
    print_test_result "true" "$0" "2" "Ghostty launches and runs a command under Xvnc"
else
    print_test_result "false" "$0" "2" "Ghostty should launch and run a command under Xvnc"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 3: the +fancy font is the one Ghostty actually loaded — a missing font
# falls back silently, so the config validating (Test 5) does not prove this.
if echo "$ACTUAL" | grep -q "font regular: JetBrainsMono"; then
    print_test_result "true" "$0" "3" "Ghostty renders with JetBrainsMono Nerd Font"
else
    print_test_result "false" "$0" "3" "Ghostty should render with JetBrainsMono Nerd Font"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 4: it registers a desktop icon (via cb-desktop-icon.sh, seeded into
# /etc/skel/Desktop).
ACTUAL=$(run_coding_booth --silence-build -- "ls /etc/skel/Desktop/com.mitchellh.ghostty.desktop" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == *"com.mitchellh.ghostty.desktop" ]]; then
    print_test_result "true" "$0" "4" "Ghostty registers a desktop icon"
else
    print_test_result "false" "$0" "4" "Ghostty should register a desktop icon"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 5: the +fancy config is seeded into the user's home at start, and
# Ghostty itself accepts every key in it.
CMD='grep -q "^background = #1a1b26" ~/.config/ghostty/config && echo SEEDED_FANCY; ghostty +validate-config >/dev/null 2>&1 && echo CONFIG_VALID'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q "SEEDED_FANCY" && echo "$ACTUAL" | grep -q "CONFIG_VALID"; then
    print_test_result "true" "$0" "5" "+fancy config is seeded and valid"
else
    print_test_result "false" "$0" "5" "+fancy config should be seeded and valid"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 6: TERM=xterm-ghostty resolves, so full-screen programs work inside it.
ACTUAL=$(run_coding_booth --silence-build -- "infocmp -x xterm-ghostty >/dev/null && echo TERMINFO_OK" 2>/dev/null)

if echo "$ACTUAL" | grep -q "TERMINFO_OK"; then
    print_test_result "true" "$0" "6" "xterm-ghostty terminfo is installed"
else
    print_test_result "false" "$0" "6" "xterm-ghostty terminfo should be installed"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 7: the checksum is enforced — a wrong --sha256 must abort before
# anything is installed, and an unpinned --version without one is refused.
CMD='S=$(command -v ghostty--setup.sh || echo /opt/codingbooth/setups/ghostty--setup.sh); '
CMD+='sudo "$S" --sha256 0000000000000000000000000000000000000000000000000000000000000000 >/dev/null 2>&1 && echo BAD_SHA_ACCEPTED || echo BAD_SHA_REJECTED; '
CMD+='sudo "$S" --version 1.2.3-0.ppa1 >/dev/null 2>&1 && echo NO_SHA_ACCEPTED || echo NO_SHA_REJECTED'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q "BAD_SHA_REJECTED" && echo "$ACTUAL" | grep -q "NO_SHA_REJECTED"; then
    print_test_result "true" "$0" "7" "a wrong or missing SHA256 is refused"
else
    print_test_result "false" "$0" "7" "a wrong or missing SHA256 should be refused"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
