#!/bin/bash
set -euo pipefail
# Claude Code is installed and prints its version (no login).
echo "=== Testing Claude Code ==="
command -v claude
claude --version
