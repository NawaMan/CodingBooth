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

# just 1.58 forwards a `--` argument separator into *args, so
# `just run -- --json 20` becomes `./run-primes.sh -- --json 20`.
while [[ "${1:-}" == -- ]]; do
    shift
done

./build/primes "$@"
