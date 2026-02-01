#!/bin/bash
echo "=== Testing Primes app ==="
cd "$(dirname "$0")"
./run-primes.sh 20 2>&1 | grep -q "2, 3, 5, 7, 11, 13, 17, 19"
