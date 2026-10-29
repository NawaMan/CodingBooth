#!/bin/bash
set -euo pipefail
# Rscript is installed and evaluates an expression
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing Rscript ==="
Rscript --version 2>&1 | grep -qi "R scripting front-end"
Rscript -e 'cat(1+2, "\n")' | grep -q 3
