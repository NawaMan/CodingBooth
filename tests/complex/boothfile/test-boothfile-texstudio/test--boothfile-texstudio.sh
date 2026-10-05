#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile TeXstudio Installation
#
# Verifies that `booth config --select latex:basic+texstudio~vscode-ext` on the
# desktop-xfce variant installs TeXstudio, registers its desktop icon, and
# produces an editor that actually starts. The command-mode booth has no
# display, so TeXstudio is launched with Qt's offscreen platform: it opens its
# main window there and must still be running when `timeout` stops it (exit
# 124). A missing library or a crash at startup exits sooner, with another code.
# The scheme is `basic` and the VS Code extension is dropped to keep the image
# small; test-boothfile-latex covers the TeX side.
#
# .booth/ is `booth config` output.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile TeXstudio Installation ==="

FAILED=0

# Test 1: TeXstudio is installed and its icon is in the desktop registry.
# Multi-line scripts throughout: a one-line `bash -c '...'` is split apart by
# COMMAND mode's re-parse (argv -> joined string -> re-parsed by bash -c).
INSTALLED_SCRIPT='
dpkg -s texstudio 2>/dev/null | grep -q "^Status: install ok installed" || { echo "not installed"; exit 0; }
[ -f /etc/skel/Desktop/texstudio.desktop ] || { echo "no desktop icon"; exit 0; }
echo installed-with-icon
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$INSTALLED_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "installed-with-icon" ]]; then
    print_test_result "true" "$0" "1" "TeXstudio is installed with a desktop icon"
else
    print_test_result "false" "$0" "1" "TeXstudio should be installed with a desktop icon"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: TeXstudio starts on a document and stays up -- no missing libraries,
# no crash at startup.
STARTS_SCRIPT='
cd /tmp
printf "%s\n" "\\documentclass{article}" "\\begin{document}hi\\end{document}" > doc.tex
missing=$(ldd /usr/bin/texstudio | grep -c "not found" || true)
[ "$missing" = "0" ] || { echo "missing libraries: $missing"; exit 0; }
env -u DISPLAY QT_QPA_PLATFORM=offscreen timeout 8 texstudio --no-session doc.tex >/dev/null 2>&1
echo "exit=$?"
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$STARTS_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "exit=124" ]]; then
    print_test_result "true" "$0" "2" "TeXstudio starts on a document and stays up"
else
    print_test_result "false" "$0" "2" "TeXstudio should start on a document and stay up"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
