#!/bin/bash
set -euo pipefail
# Node.js, Bun and Deno are installed and run a one-liner.
echo "=== Testing JS runtimes ==="
node --version
node -e "console.log('node ok')" | grep -q "node ok"
bun --version
bun -e "console.log('bun ok')" | grep -q "bun ok"
deno --version
deno eval "console.log('deno ok')" | grep -q "deno ok"
