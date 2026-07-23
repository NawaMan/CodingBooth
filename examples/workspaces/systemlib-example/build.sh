#!/bin/bash
# Configure (with clang) and build the link checker into ./build/linkcheck.
# CMake's find_package resolves libcurl and SQLite here; a missing -dev package
# makes this step fail loudly.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -d build ]]; then
    cmake -S . -B build \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_BUILD_TYPE=Release
fi
cmake --build build -j
