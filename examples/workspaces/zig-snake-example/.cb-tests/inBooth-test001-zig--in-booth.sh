#!/bin/bash
set -euo pipefail
# Zig 0.15.1 and Claude Code are installed.
echo "=== Testing Zig ==="
zig version | grep -q '^0\.15\.1'
claude --version
