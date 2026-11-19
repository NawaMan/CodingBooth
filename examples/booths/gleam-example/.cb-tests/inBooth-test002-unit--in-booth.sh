#!/bin/bash
echo "=== Testing router (gleam test) ==="
cd "$(dirname "$0")/.."
just test 2>&1 | tee /tmp/gleam-test.out
grep -q " passed, no failures" /tmp/gleam-test.out
