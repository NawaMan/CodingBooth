#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Kitty Installation
#
# Kitty is GPU-accelerated (OpenGL) and normally needs a desktop session, but
# a booth's desktop has no host GPU either — it renders headless through
# Mesa's llvmpipe software rasterizer. This test proves that actually works:
# it starts a throwaway Xvnc session inside the container and launches Kitty
# against it, rather than only checking the binary is on PATH. It also pins
# down that Kitty comes from the checksum-verified upstream release rather than
# Ubuntu's apt build, which lags on security fixes.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Kitty Installation ==="

FAILED=0

# Test 1: kitty is on PATH and reports a version
ACTUAL=$(run_coding_booth --silence-build -- "kitty --version" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" =~ ^kitty\  ]]; then
    print_test_result "true" "$0" "1" "Kitty is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Kitty should be installed"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: it actually runs — start a throwaway Xvnc, launch Kitty against it,
# and have the shell it opens write a marker file. Kitty renders that shell in
# its own pty/window rather than the outer shell's stdout (so its own exit
# code doesn't reflect the child's either), so a file the child wrote is the
# only reliable way to observe what happened inside it.
CMD='Xvnc :1 -geometry 1280x800 -localhost yes -SecurityTypes=None >/tmp/xvnc.log 2>&1 & sleep 2; DISPLAY=:1 timeout 10 kitty sh -c "echo KITTY_RAN_OK > /tmp/kitty-marker.txt"; sleep 1; cat /tmp/kitty-marker.txt 2>/dev/null'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q "KITTY_RAN_OK"; then
    print_test_result "true" "$0" "2" "Kitty launches and runs a command under Xvnc"
else
    print_test_result "false" "$0" "2" "Kitty should launch and run a command under Xvnc"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 3: it registers a desktop icon (via cb-desktop-icon.sh, seeded into
# /etc/skel/Desktop) — without this, a user has no way to discover it besides
# already knowing the command name.
ACTUAL=$(run_coding_booth --silence-build -- "ls /etc/skel/Desktop/kitty.desktop" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == *"kitty.desktop" ]]; then
    print_test_result "true" "$0" "3" "Kitty registers a desktop icon"
else
    print_test_result "false" "$0" "3" "Kitty should register a desktop icon"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 4: it is the upstream release, not Ubuntu's apt build. noble's kitty
# 0.32.2 is exposed to CVE-2026-72913 (fixed 0.48.2), where displaying untrusted
# output can run commands — Test 1 alone would pass on that too. Where it is
# installed from is the point, not which release it is.
ACTUAL=$(run_coding_booth --silence-build -- "readlink -f /usr/local/bin/kitty" 2>/dev/null)

if echo "$ACTUAL" | grep -q "^/opt/kitty/bin/kitty$"; then
    print_test_result "true" "$0" "4" "Kitty is the upstream release from /opt/kitty"
else
    print_test_result "false" "$0" "4" "Kitty should be the upstream release from /opt/kitty"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 5: TERM=xterm-kitty resolves — the apt package brought this in via
# kitty-terminfo; the upstream install has to place it itself.
ACTUAL=$(run_coding_booth --silence-build -- "infocmp -x xterm-kitty >/dev/null && echo TERMINFO_OK" 2>/dev/null)

if echo "$ACTUAL" | grep -q "TERMINFO_OK"; then
    print_test_result "true" "$0" "5" "xterm-kitty terminfo is installed"
else
    print_test_result "false" "$0" "5" "xterm-kitty terminfo should be installed"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 6: the checksum is enforced — a wrong --sha256 must abort before anything
# is extracted, and an unpinned --version without one is refused outright.
CMD='S=$(command -v kitty--setup.sh || echo /opt/codingbooth/setups/kitty--setup.sh); '
CMD+='sudo "$S" --sha256 0000000000000000000000000000000000000000000000000000000000000000 >/dev/null 2>&1 && echo BAD_SHA_ACCEPTED || echo BAD_SHA_REJECTED; '
CMD+='sudo "$S" --version 0.48.2 >/dev/null 2>&1 && echo NO_SHA_ACCEPTED || echo NO_SHA_REJECTED'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q "BAD_SHA_REJECTED" && echo "$ACTUAL" | grep -q "NO_SHA_REJECTED"; then
    print_test_result "true" "$0" "6" "a wrong or missing SHA256 is refused"
else
    print_test_result "false" "$0" "6" "a wrong or missing SHA256 should be refused"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 7: the +fancy config is seeded into the user's home at start, and Kitty
# loads it cleanly — it prints "Ignoring unknown config key" / "Ignoring
# invalid config line" for anything it does not accept, and with
# --debug-font-fallback names the font file it resolved, so one launch proves
# both the keys and the JetBrains Mono font (a missing font falls back
# silently otherwise).
CMD='grep -q "^background  *#1a1b26" ~/.config/kitty/kitty.conf && echo SEEDED_FANCY; '
CMD+='Xvnc :1 -geometry 1280x800 -localhost yes -SecurityTypes=None >/tmp/xvnc.log 2>&1 & sleep 2; '
CMD+='DISPLAY=:1 timeout 10 kitty --debug-font-fallback sh -c "sleep 1" >/tmp/kitty.log 2>&1; '
CMD+='grep -qi "Ignoring" /tmp/kitty.log && echo CONFIG_COMPLAINED; '
CMD+='grep -q "Normal: JetBrainsMonoNF-Regular" /tmp/kitty.log && echo FONT_JETBRAINS'
ACTUAL=$(run_coding_booth --silence-build -- "$CMD" 2>/dev/null)

if echo "$ACTUAL" | grep -q "SEEDED_FANCY" && ! echo "$ACTUAL" | grep -q "CONFIG_COMPLAINED"; then
    print_test_result "true" "$0" "7" "+fancy config is seeded and Kitty accepts every key"
else
    print_test_result "false" "$0" "7" "+fancy config should be seeded and accepted"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 8: the +fancy font is the one Kitty actually renders with.
if echo "$ACTUAL" | grep -q "FONT_JETBRAINS"; then
    print_test_result "true" "$0" "8" "Kitty renders with JetBrainsMono Nerd Font"
else
    print_test_result "false" "$0" "8" "Kitty should render with JetBrainsMono Nerd Font"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
