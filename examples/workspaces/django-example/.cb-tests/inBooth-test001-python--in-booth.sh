#!/bin/bash
set -euo pipefail
# Checks Python 3.13 with pip/uv, and that the project's requirements.txt is present.
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing Python (django-example) ==="
python --version | grep -qE 'Python 3\.13'
python -m pip --version
python -c 'import sys, venv; print(sys.prefix)'
test -f requirements.txt
echo "PASS"
