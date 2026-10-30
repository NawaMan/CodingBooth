#!/bin/bash
set -euo pipefail
# Checks the omp (oh-my-pi) CLI is installed (no login).
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing omp ==="
command -v omp
omp --version | grep -qE 'omp/[0-9]'
echo "PASS"
