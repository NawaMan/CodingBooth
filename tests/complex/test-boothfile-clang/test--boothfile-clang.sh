#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Clang Installation
#
# Verifies that a Boothfile with `setup clang --version 18` correctly installs
# the LLVM/Clang toolchain (clang, clang++, clangd, clang-format, clang-tidy)
# and registers it as the default C/C++ compiler.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

# Needs a locally-rebuilt base image because the Hub clang--setup.sh tries to
# install LLVM 18 from apt.llvm.org's snapshot repo, which currently 404s on
# its own internal version constraint (libllvm18 Breaks llvm-18-dev < 1:18.1.8-8).
use_local_base_image || exit 0

echo "=== Test: Boothfile Clang Installation ==="

FAILED=0

# Test 1: clang is installed
ACTUAL=$(run_coding_booth --silence-build -- clang --version 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if echo "$ACTUAL" | grep -qE "clang version 18"; then
    print_test_result "true" "$0" "1" "Clang 18 is installed"
else
    print_test_result "false" "$0" "1" "Clang 18 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: clang++ is installed
ACTUAL=$(run_coding_booth --silence-build -- clang++ --version 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if echo "$ACTUAL" | grep -qE "clang version 18"; then
    print_test_result "true" "$0" "2" "Clang++ 18 is installed"
else
    print_test_result "false" "$0" "2" "Clang++ 18 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: clangd is installed (used by IDE/LSP integrations)
ACTUAL=$(run_coding_booth --silence-build -- clangd --version 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if echo "$ACTUAL" | grep -qE "clangd"; then
    print_test_result "true" "$0" "3" "clangd is installed"
else
    print_test_result "false" "$0" "3" "clangd should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: clang is registered as the default cc (via update-alternatives)
ACTUAL=$(run_coding_booth --silence-build -- 'cc --version' 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if echo "$ACTUAL" | grep -qE "clang"; then
    print_test_result "true" "$0" "4" "Clang is the default 'cc' compiler"
else
    print_test_result "false" "$0" "4" "Clang should be the default 'cc'"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: a simple C++ program compiles and runs.
# Heredoc avoids quote-mangling when the command round-trips through
# codingbooth's COMMAND mode (argv -> joined string -> re-parsed by bash -c).
COMPILE_RUN_SCRIPT='
cat > /tmp/t.cpp <<EEE
int main(){return 42;}
EEE
clang++ /tmp/t.cpp -o /tmp/t
/tmp/t
echo $?
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$COMPILE_RUN_SCRIPT" 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "42" ]]; then
    print_test_result "true" "$0" "5" "Clang++ compiles and runs a C++ program"
else
    print_test_result "false" "$0" "5" "Clang++ should compile and run a C++ program"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
