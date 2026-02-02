#!/bin/bash
echo "=== Testing Fibonacci app ==="
cd "$(dirname "$0")"
./run-fibonacci.sh 10 | grep -q "F(9) = 34"
