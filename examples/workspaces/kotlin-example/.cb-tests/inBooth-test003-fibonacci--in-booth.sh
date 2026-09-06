#!/bin/bash
echo "=== Testing Fibonacci app ==="
cd "$(dirname "$0")/.."
just run 10 | grep -q "F(9) = 34"
