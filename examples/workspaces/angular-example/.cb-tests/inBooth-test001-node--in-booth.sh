#!/bin/bash
set -euo pipefail
# Checks Node 22 and npm are installed, and the project's package.json is present.
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing Node.js (Angular example) ==="
node --version | grep -qE '^v22\.'
npm --version
test -f package.json
grep -q '@angular/core' package.json
echo "PASS"
