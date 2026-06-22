#!/bin/bash
# Test: primes --json, which uses the apt-installed nlohmann/json C++ library.
set -euo pipefail
echo "=== Testing primes --json (uses apt-installed nlohmann/json) ==="
cd "$(dirname "$0")/.."
./run-primes.sh --json 20 2>&1 | grep -qF '[2,3,5,7,11,13,17,19]'
