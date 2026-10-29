#!/bin/bash
set -euo pipefail
# The Firebase CLI and Claude Code are installed and print versions (no login).
echo "=== Testing Firebase CLI ==="
command -v firebase
firebase --version
command -v claude
claude --version
