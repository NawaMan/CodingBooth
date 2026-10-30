#!/bin/bash
set -euo pipefail
# claude CLI is installed and prints a version (no login, no network policy check)
echo "=== Testing claude ==="
command -v claude
claude --version
