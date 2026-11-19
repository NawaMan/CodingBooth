#!/bin/bash
set -euo pipefail
# alacritty and kitty binaries are installed (no display needed)
echo "=== Testing alacritty and kitty ==="
command -v alacritty
alacritty --version
command -v kitty
kitty --version
