#!/bin/bash
echo "=== Testing AFFiNE Server UI ==="
cd "$(dirname "$0")/.."
just run 2>&1 | grep -q "AFFiNE Server is up"
