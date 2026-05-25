#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Full C/C++ Toolchain
#
# Verifies that clang, gcc, cmake, and make can be installed together via a
# single Boothfile. Confirms:
#   - clang is the default cc (priority 100 wins over gcc's 50)
#   - gcc remains usable explicitly
#   - cmake configures and builds a tiny project end-to-end
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

# Depends on the locally-rebuilt base image (uses clang--setup.sh; the Hub
# image fails with apt.llvm.org's libllvm18/llvm-18-dev snapshot conflict).
use_local_base_image || exit 0

echo "=== Test: Boothfile Full C/C++ Toolchain ==="

FAILED=0

# Test 1: clang is installed
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- clang --version)
if echo "$ACTUAL" | grep -qE "clang version 18"; then
    print_test_result "true" "$0" "1" "Clang 18 is installed alongside GCC"
else
    print_test_result "false" "$0" "1" "Clang 18 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: gcc is installed
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- gcc --version)
if echo "$ACTUAL" | grep -qE "gcc.* 13\."; then
    print_test_result "true" "$0" "2" "GCC 13 is installed alongside Clang"
else
    print_test_result "false" "$0" "2" "GCC 13 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: clang wins as the default cc (update-alternatives priority 100 vs 50)
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'cc --version')
if echo "$ACTUAL" | grep -qE "clang"; then
    print_test_result "true" "$0" "3" "Clang is the default 'cc' (priority wins)"
else
    print_test_result "false" "$0" "3" "Clang should be the default 'cc' when both compilers are installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: cmake is installed
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- cmake --version)
if echo "$ACTUAL" | grep -qE "cmake version"; then
    print_test_result "true" "$0" "4" "CMake is installed"
else
    print_test_result "false" "$0" "4" "CMake should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: make is installed
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- make --version)
if echo "$ACTUAL" | grep -qE "GNU Make"; then
    print_test_result "true" "$0" "5" "GNU Make is installed"
else
    print_test_result "false" "$0" "5" "GNU Make should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 6: end-to-end CMake build using clang
BUILD_SCRIPT='
set -e
mkdir -p /tmp/cppbuild/src && cd /tmp/cppbuild
cat > CMakeLists.txt <<CML
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
add_executable(t src/m.cpp)
CML
cat > src/m.cpp <<CPP
#include <iostream>
int main(){ std::cout << "build-ok" << std::endl; return 0; }
CPP
cmake -S . -B build -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build -j >/dev/null
./build/t
'
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- bash -c "$BUILD_SCRIPT")
if [[ "$ACTUAL" == "build-ok" ]]; then
    print_test_result "true" "$0" "6" "CMake builds a C++ binary using clang"
else
    print_test_result "false" "$0" "6" "CMake should build a C++ binary using clang"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 7: end-to-end CMake build using gcc (explicit)
BUILD_SCRIPT_GCC='
set -e
mkdir -p /tmp/gccbuild/src && cd /tmp/gccbuild
cat > CMakeLists.txt <<CML
cmake_minimum_required(VERSION 3.16)
project(t LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
add_executable(t src/m.cpp)
CML
cat > src/m.cpp <<CPP
#include <iostream>
int main(){ std::cout << "gcc-build-ok" << std::endl; return 0; }
CPP
cmake -S . -B build -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build -j >/dev/null
./build/t
'
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- bash -c "$BUILD_SCRIPT_GCC")
if [[ "$ACTUAL" == "gcc-build-ok" ]]; then
    print_test_result "true" "$0" "7" "CMake builds a C++ binary using explicit gcc/g++"
else
    print_test_result "false" "$0" "7" "CMake should build a C++ binary using gcc/g++"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
