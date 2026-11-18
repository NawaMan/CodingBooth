#!/bin/bash
set -euo pipefail
# python 3.13 is installed (notebook kernel runtime)
echo "=== Testing python ==="
python --version | grep -q 'Python 3\.13'
