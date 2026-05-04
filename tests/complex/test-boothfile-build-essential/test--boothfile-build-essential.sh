#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile build-essential Installation
#
# Verifies that `setup build-essential` provides the standard Ubuntu toolchain
# (gcc, g++, make, pkg-config) without /opt layout, so it stays out of the way
# of pinned `setup gcc --version N` / `setup clang --version N` installs.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile build-essential Installation ==="

FAILED=0

# Test 1: gcc is available (apt default version)
ACTUAL=$(run_coding_booth --silence-build -- gcc --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -qE "gcc"; then
    print_test_result "true" "$0" "1" "gcc is installed via build-essential"
else
    print_test_result "false" "$0" "1" "gcc should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: g++ is available
ACTUAL=$(run_coding_booth --silence-build -- g++ --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -qE "g\+\+"; then
    print_test_result "true" "$0" "2" "g++ is installed via build-essential"
else
    print_test_result "false" "$0" "2" "g++ should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: make is available
ACTUAL=$(run_coding_booth --silence-build -- make --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -qE "GNU Make"; then
    print_test_result "true" "$0" "3" "make is installed via build-essential"
else
    print_test_result "false" "$0" "3" "make should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: pkg-config is available (the bridge to system libraries)
ACTUAL=$(run_coding_booth --silence-build -- pkg-config --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -qE "^[0-9]+\."; then
    print_test_result "true" "$0" "4" "pkg-config is installed"
else
    print_test_result "false" "$0" "4" "pkg-config should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: a tiny C program compiles & runs end-to-end.
# Using a heredoc rather than `echo "..." > file` because the embedded quotes
# get mangled when the command is round-tripped through codingbooth's COMMAND
# mode (argv -> joined string -> re-parsed by bash -c).
COMPILE_RUN_SCRIPT='
cat > /tmp/t.c <<EEE
int main(){return 5;}
EEE
gcc /tmp/t.c -o /tmp/t
/tmp/t
echo $?
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$COMPILE_RUN_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "5" ]]; then
    print_test_result "true" "$0" "5" "gcc compiles and runs a C program"
else
    print_test_result "false" "$0" "5" "gcc should compile and run a C program"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
