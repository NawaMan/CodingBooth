#!/bin/bash
echo "=== Testing the primes demo (in-process run) ==="
cd "$(dirname "$0")/.."
out="$(just run 20 2>/dev/null)"
echo "$out" | tr '\n' ' ' | grep -q "^2 3 5 7 11 13 17 19 Found 8 primes up to 20" \
    || { echo "unexpected output:"; echo "$out"; exit 1; }
