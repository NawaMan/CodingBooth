#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile GCC Installation
#
# Verifies that a Boothfile with `setup gcc --version 13` correctly installs
# the GNU Compiler Collection (gcc + g++) at the requested version.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile GCC Installation ==="

FAILED=0

# Test 1: gcc is installed at the requested version
ACTUAL=$(run_coding_booth --silence-build -- gcc --version 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if echo "$ACTUAL" | grep -qE "gcc.* 13\."; then
    print_test_result "true" "$0" "1" "GCC 13 is installed"
else
    print_test_result "false" "$0" "1" "GCC 13 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: g++ is installed at the requested version
ACTUAL=$(run_coding_booth --silence-build -- g++ --version 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if echo "$ACTUAL" | grep -qE "g\+\+.* 13\."; then
    print_test_result "true" "$0" "2" "G++ 13 is installed"
else
    print_test_result "false" "$0" "2" "G++ 13 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: a simple C program compiles and runs.
# Heredoc avoids quote-mangling when the command round-trips through
# codingbooth's COMMAND mode (argv -> joined string -> re-parsed by bash -c).
COMPILE_RUN_C_SCRIPT='
cat > /tmp/t.c <<EEE
int main(){return 7;}
EEE
gcc /tmp/t.c -o /tmp/t
/tmp/t
echo $?
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$COMPILE_RUN_C_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "7" ]]; then
    print_test_result "true" "$0" "3" "GCC compiles and runs a C program"
else
    print_test_result "false" "$0" "3" "GCC should compile and run a C program"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: a simple C++ program compiles and runs.
COMPILE_RUN_CPP_SCRIPT='
cat > /tmp/t.cpp <<EEE
#include <iostream>
int main(){ std::cout << "ok" << std::endl; return 0; }
EEE
g++ /tmp/t.cpp -o /tmp/t
/tmp/t
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$COMPILE_RUN_CPP_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "ok" ]]; then
    print_test_result "true" "$0" "4" "G++ compiles and runs a C++ program"
else
    print_test_result "false" "$0" "4" "G++ should compile and run a C++ program"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
