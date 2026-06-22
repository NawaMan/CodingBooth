#!/bin/bash
# Test: jq (installed via `install apt jq`)

set -euo pipefail

echo "=== Testing jq ==="
jq --version
echo '{"tool":"jq"}' | jq -r .tool
