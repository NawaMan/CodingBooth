#!/bin/bash
set -euo pipefail
# clang++ and python are installed; main.cpp compiles and runs
echo "=== Testing clang and python ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
clang++ --version | grep -q clang
python --version | grep -q 'Python 3\.13'
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
clang++ main.cpp -o "$tmp/main"
"$tmp/main" >/dev/null
