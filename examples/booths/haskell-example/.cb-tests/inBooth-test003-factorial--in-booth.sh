#!/bin/bash
echo "=== Testing Factorial app ==="
cd "$(dirname "$0")/.."
just run 5 | grep -q "120"
