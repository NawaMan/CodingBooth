#!/bin/bash
# Build with clang++ and run main.
# Uses `make` if available; falls back to direct clang++ otherwise (useful when
# the Boothfile installs only `setup clang ...` without a build-system setup).
set -euo pipefail
cd "$(dirname "$0")"

if command -v make >/dev/null 2>&1; then
    make
else
    echo "make not found — compiling directly with clang++"
    clang++ -std=c++17 -O2 -Wall -Wextra main.cpp -o main
fi

./main
