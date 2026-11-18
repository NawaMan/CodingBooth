#!/bin/bash
set -euo pipefail
# python 3.13 is installed and the www folder is servable
echo "=== Testing python and www ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
python --version | grep -q 'Python 3\.13'
python -c 'import http.server'
test -d www
test -x start-server.sh
