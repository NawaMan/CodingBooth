#!/bin/bash
set -euo pipefail
# omp (oh-my-pi) CLI is installed and runs (no login)
echo "=== Testing omp ==="
command -v omp
omp --version | grep -qE 'omp/[0-9]'
