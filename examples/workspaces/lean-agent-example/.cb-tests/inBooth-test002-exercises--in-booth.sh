#!/bin/bash
echo "=== Testing the exercises build, with every proof still to write ==="
cd "$(dirname "$0")/.."
just build 2>&1 | tee /tmp/agent-build.out | tail -4
grep -q "Build completed successfully" /tmp/agent-build.out || { echo "  ✗ lake build failed"; exit 1; }
n="$(grep -c "declaration uses .sorry." /tmp/agent-build.out)"
# 5 = every exercise open. A different count means the exercises were edited (or solved).
[[ "$n" == 5 ]] || { echo "  ✗ expected 5 open exercises, found $n"; exit 1; }
echo "  ✓ builds; 5 exercises open (sorry)"
