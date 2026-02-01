#!/bin/bash
echo "=== Testing Stats app ==="
cd "$(dirname "$0")"
./run-stats.sh 1 2 3 4 5 | grep -q "Mean:"
