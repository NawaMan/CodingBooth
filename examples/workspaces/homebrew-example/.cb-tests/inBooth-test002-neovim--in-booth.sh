#!/bin/bash
# Test: neovim

echo "=== Testing neovim ==="
nvim --version | head -1
echo 'print("nvim works")' | nvim --headless -c '%print' -c 'q!' 2>/dev/null
