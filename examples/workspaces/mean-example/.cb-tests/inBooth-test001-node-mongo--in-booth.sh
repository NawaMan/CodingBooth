#!/bin/bash
set -euo pipefail
# node, npm and mongodb binaries are installed
echo "=== Testing node and mongodb ==="
node --version | grep -qE '^v22\.'
npm --version
command -v mongod
mongod --version | grep -qi 'db version'
