#!/bin/bash
set -euo pipefail
# Checks Python 3.13 (http.server module) and the claude CLI are installed, and www/index.html exists.
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing server-example-2 tools ==="
python --version | grep -qE 'Python 3\.13'
python -c 'import http.server'
command -v claude
claude --version
test -f www/index.html
echo "PASS"
