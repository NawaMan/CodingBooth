#!/bin/bash
set -euo pipefail
# node 22 and npm are installed; project has a package.json
echo "=== Testing node for Next.js ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
node --version | grep -qE '^v22\.'
npm --version
test -f package.json
