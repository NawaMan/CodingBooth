#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile TTT installation
#
# ttt --version only proves a binary landed on PATH. --exec types into a file,
# saves it, and quits: that is the edit a user does in the first minute.
# rg --version proves workspace search has its dependency. The fixture is
# `ttt+theme:nord,double/lsp`, so ttt+lsp comes selected with ttt and lsp+markdown
# with lsp. ttt+theme pins values other than the base default (zenith, rounded) to
# prove they reach the base image's theme start-up; the plain-booth default is
# tests/basic/test041. The start-up also seeds the marksman entry, and TTT opening
# a Markdown file must reach a connected server (Markdown ◉ in the status bar).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile TTT Installation ==="

FAILED=0

ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'ttt --version')
if [[ "$ACTUAL" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
    print_test_result "true" "$0" "1" "ttt --version reports a release"
else
    print_test_result "false" "$0" "1" "ttt --version should report a release"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'rg --version')
if [[ "$ACTUAL" == ripgrep* ]]; then
    print_test_result "true" "$0" "2" "ripgrep is installed for TTT workspace search"
else
    print_test_result "false" "$0" "2" "rg --version should report ripgrep"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# type inserts at the start of the buffer. ctrl+s is file.save.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'd=$(mktemp -d) && printf "alpha\n" > "$d/note.txt" && ttt "$d/note.txt" --size 80x24 --exec "type Z; key ctrl+s; quit" && cat "$d/note.txt"')
if [[ "$ACTUAL" == Z* ]]; then
    print_test_result "true" "$0" "3" "ttt --exec types into a file and saves it"
else
    print_test_result "false" "$0" "3" "ttt --exec should save the typed character"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'jq -c "[.theme, .editor.borderStyle, .lsp.servers.markdown.command]" ~/.config/ttt/settings.json')
if [[ "$ACTUAL" == '["nord","double",["marksman","server"]]' ]]; then
    print_test_result "true" "$0" "4" "start-up seeds ttt+theme's nord and double, and marksman"
else
    print_test_result "false" "$0" "4" "settings.json should hold nord, double, and the marksman entry"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# wait-for fails the --exec, and the command, when the text never appears.
# The status bar pads its segments, so the gap before ◉ is one or more spaces.
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'd=$(mktemp -d) && printf "# Notes\n\nSee [Notes](#notes).\n" > "$d/notes.md" && ttt "$d/notes.md" --size 100x24 --exec "wait-for ◉ timeout=60000; screenshot $d/screen.txt; quit" && tail -1 "$d/screen.txt"')
CONNECTED='Markdown +◉'
if [[ "$ACTUAL" =~ $CONNECTED ]]; then
    print_test_result "true" "$0" "5" "ttt connects to marksman for a Markdown file"
else
    print_test_result "false" "$0" "5" "ttt should show Markdown ◉ (connected) for a .md file"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
