#!/bin/bash
set -euo pipefail
# Checks Node 22, npm, and the MongoDB server/shell binaries (does not start mongod).
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing MERN tools ==="
node --version | grep -qE '^v22\.'
npm --version
command -v mongod
mongod --version | head -1
command -v mongosh
mongosh --version
test -f server/package.json
test -f client/package.json
echo "PASS"
