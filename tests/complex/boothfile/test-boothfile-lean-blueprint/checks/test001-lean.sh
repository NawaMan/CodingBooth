#!/bin/bash
echo "=== Testing the Lean project builds, with exactly the one intended sorry ==="
cd "$(dirname "$0")/.."
lake build 2>&1 | tee /tmp/bp-build.out
grep -q "Build completed successfully" /tmp/bp-build.out || { echo "  ✗ lake build failed"; exit 1; }
sorries="$(grep -c "declaration uses .sorry." /tmp/bp-build.out)"
grep -q "Cubes.lean:.*declaration uses .sorry." /tmp/bp-build.out && [[ "$sorries" == 1 ]] \
    || { echo "  ✗ expected exactly one sorry (Nicomachus, in Cubes.lean), found ${sorries}"; exit 1; }
echo "  ✓ builds; the only sorry is Nicomachus"
