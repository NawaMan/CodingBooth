#!/bin/bash
set -euo pipefail
# python is installed, and app.py is valid Python
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing python ==="
python --version | grep -q "Python 3"
python -m py_compile app.py
rm -rf __pycache__
