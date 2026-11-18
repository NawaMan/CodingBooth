#!/bin/bash
echo "=== Testing Floci S3 round-trip ==="
cd "$(dirname "$0")/.."
just run 2>&1 | grep -q "hello from floci"
