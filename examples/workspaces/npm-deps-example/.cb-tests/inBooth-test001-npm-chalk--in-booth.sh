#!/bin/bash
set -euo pipefail
# Node.js and npm are installed and the chalk dependency from package.json resolves.
echo "=== Testing npm and chalk ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
node --version
npm --version
# the booth pre-installs into /opt/npm-cache; a replayed provision may use node_modules here
for d in "$PWD" /opt/npm-cache; do
    if [ -d "$d/node_modules/chalk" ]; then
        (cd "$d" && node -e "require('chalk'); console.log('OK')") | grep -q OK
        exit 0
    fi
done
node -e "require('chalk'); console.log('OK')" | grep -q OK
