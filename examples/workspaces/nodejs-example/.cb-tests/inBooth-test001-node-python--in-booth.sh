#!/bin/bash
set -euo pipefail
# Checks Node 22, npm, Python 3.13, the claude CLI, and Jupyter (notebook setup) are installed.
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing Node.js + Python + notebook ==="
node --version | grep -qE '^v22\.'
npm --version
python --version | grep -qE 'Python 3\.13'
command -v claude
claude --version
python -c 'import jupyterlab' 2>/dev/null || command -v jupyter
test -f hello-js.ipynb
echo "PASS"
