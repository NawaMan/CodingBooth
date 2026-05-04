#!/bin/bash
set -euo pipefail
echo "=== Testing primes app (clang + cmake build) ==="
cd "$(dirname "$0")/.."
./run-primes.sh 20 2>&1 | grep -q "2, 3, 5, 7, 11, 13, 17, 19"
