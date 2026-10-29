#!/bin/bash
set -euo pipefail
# python 3.13 is installed and Main.py runs
echo "=== Testing python and Main.py ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
python --version | grep -q 'Python 3\.13'
python Main.py >/dev/null
command -v claude
