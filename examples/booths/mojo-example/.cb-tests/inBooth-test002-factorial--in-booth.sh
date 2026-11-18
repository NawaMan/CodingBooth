#!/bin/bash
echo "=== Testing Factorial app ==="
cd "$(dirname "$0")/.."
just run 5 2>&1 | grep -q "5! = 120"
