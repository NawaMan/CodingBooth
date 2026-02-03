#!/bin/bash
echo "=== Testing Factorial app ==="
cd "$(dirname "$0")/.."
./run-factorial.sh 5 | grep -q "120"
