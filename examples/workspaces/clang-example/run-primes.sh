#!/bin/bash
# Configure with clang, build, and run the primes program.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -d build ]]; then
    cmake -S . -B build \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_BUILD_TYPE=Release
fi
cmake --build build -j

./build/primes "$@"
