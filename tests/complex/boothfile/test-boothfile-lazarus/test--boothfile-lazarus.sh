#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Lazarus (fpc+lazarus) on the base variant
#
# Without a desktop, `setup lazarus` installs lazbuild + the LCL but no IDE.
# Proves lazbuild builds real projects headless: an LCL (GTK2) GUI program
# compiles and links, and a LazUtils console program builds and runs. Also
# checks the LCL was prebuilt into the image, so the user's build compiles
# only the project itself.
#
# lazarus--setup.sh is supplied under .booth/setups/ until the base image ships it.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile Lazarus ==="

FAILED=0

# Projects are copied out of the mounted fixture so build output never lands in the repo.
# Heredoc-free on purpose: the command round-trips through codingbooth's COMMAND mode.
BUILD_SCRIPT='
rm -rf /tmp/laz && mkdir -p /tmp/laz && cp -r gui cli /tmp/laz/
cd /tmp/laz/gui && lazbuild hello.lpi > /tmp/laz/gui.log 2>&1 && echo "GUI_BUILT"
grep -c "Compiling " /tmp/laz/gui.log | sed "s/^/GUI_UNITS=/"
head -c4 /tmp/laz/gui/hello | grep -q ELF && echo "GUI_ELF"
cd /tmp/laz/cli && lazbuild -q greet.lpi > /tmp/laz/cli.log 2>&1 && ./greet
command -v lazarus-ide >/dev/null && echo "IDE_PRESENT" || echo "IDE_ABSENT"
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$BUILD_SCRIPT" 2>/dev/null) || ACTUAL=""

# Test 1: an LCL GUI program compiles and links (needs the gtk2 link libs)
if echo "$ACTUAL" | grep -q "^GUI_BUILT" && echo "$ACTUAL" | grep -q "^GUI_ELF"; then
    print_test_result "true" "$0" "1" "lazbuild builds an LCL GUI program headless"
else
    print_test_result "false" "$0" "1" "lazbuild should build an LCL GUI program headless"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: the LCL came prebuilt — the user's build compiles the project, not the LCL
UNITS=$(echo "$ACTUAL" | sed -n 's/^GUI_UNITS=//p')
if [[ -n "$UNITS" && "$UNITS" -le 3 ]]; then
    print_test_result "true" "$0" "2" "LCL is prebuilt ($UNITS units compiled)"
else
    print_test_result "false" "$0" "2" "LCL should be prebuilt (compiled: ${UNITS:-?} units)"
    FAILED=$((FAILED + 1))
fi

# Test 3: a LazUtils console program builds and runs
if echo "$ACTUAL" | grep -q "^lazutils OK greet$"; then
    print_test_result "true" "$0" "3" "lazbuild builds and runs a LazUtils program"
else
    print_test_result "false" "$0" "3" "lazbuild should build and run a LazUtils program"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: no desktop, so no IDE
if echo "$ACTUAL" | grep -q "^IDE_ABSENT"; then
    print_test_result "true" "$0" "4" "no IDE on the base variant"
else
    print_test_result "false" "$0" "4" "the IDE should not be installed without a desktop"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
