#!/bin/bash
set -euo pipefail
# Checks Node 24 and the codex CLI are installed (no login).
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing codex ==="
node --version | grep -qE '^v24\.'
command -v codex
codex --version | grep -q 'codex-cli'
echo "PASS"
