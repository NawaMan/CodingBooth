#!/bin/bash
set -euo pipefail
# JupyterLab is installed and the Sales Explorer notebook is in the project.
echo "=== Testing notebook ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
command -v jupyter
# Capture first: `jupyter --version | grep -q` under pipefail breaks jupyter's pipe.
versions="$(jupyter --version)"; echo "$versions"
[ -n "$versions" ]
test -f Sales-Explorer.ipynb
