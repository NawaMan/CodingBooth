#!/bin/bash
echo "=== Testing a native build (goose-lang build, via gcc) ==="
cd "$(dirname "$0")/.."
trap 'rm -f primes' EXIT
just build || exit 1
./primes 30 | tail -1 | grep -qx "Found 10 primes up to 30" \
    || { echo "unexpected output: $(./primes 30 | tail -1)"; exit 1; }
