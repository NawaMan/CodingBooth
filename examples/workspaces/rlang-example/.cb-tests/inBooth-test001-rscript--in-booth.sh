#!/bin/bash
set -euo pipefail
# Rscript is installed and evaluates an expression
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing Rscript ==="
# Capture first: `cmd | grep -q` under pipefail fails when grep exits before cmd is done writing.
version="$(Rscript --version 2>&1)"; echo "$version"
grep -q "Rscript (R) version" <<< "$version"
result="$(Rscript -e 'cat(1+2, "\n")')"; echo "1+2 = $result"
grep -q 3 <<< "$result"
