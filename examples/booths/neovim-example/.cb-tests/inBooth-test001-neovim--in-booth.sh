#!/bin/bash
set -euo pipefail
# nvim and claude are installed
echo "=== Testing neovim ==="
nvim --version | grep -q "NVIM"
echo "=== Testing claude ==="
claude --version
