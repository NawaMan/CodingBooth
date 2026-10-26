#!/bin/bash
echo "=== Testing the Mathlib cache and the proofs ==="
cd "$(dirname "$0")/.."
fail=0
just cache 2>&1 | tail -3
# The cache must make Mathlib a download, not a build: nothing of Mathlib may compile here.
just build 2>&1 | grep -v '^trace' | tee /tmp/mathlib-build.out | tail -8
grep -q "Build completed successfully" /tmp/mathlib-build.out || { echo "  ✗ lake build failed"; fail=1; }
if grep -qE "Built Mathlib\.|Building Mathlib\." /tmp/mathlib-build.out; then
    echo "  ✗ Mathlib was compiled, not downloaded"; fail=1
else
    echo "  ✓ Mathlib came from the cache"
fi
if grep -qiE "warning|sorry" /tmp/mathlib-build.out; then
    echo "  ✗ the build has warnings or sorry"; grep -iE "warning|sorry" /tmp/mathlib-build.out; fail=1
else
    echo "  ✓ every proof checks, no warnings, no sorry"
fi
exit $fail
