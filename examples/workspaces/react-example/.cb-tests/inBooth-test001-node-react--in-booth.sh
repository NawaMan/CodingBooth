#!/bin/bash
set -euo pipefail
# Node.js 22 and npm are installed and the project declares React.
echo "=== Testing Node.js and React ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
node --version | grep -q '^v22'
npm --version
grep -q '"react"' package.json
