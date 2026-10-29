#!/bin/bash
set -euo pipefail
# codex CLI is installed and runs (no login)
echo "=== Testing codex ==="
command -v codex
codex --version | grep -qE '[0-9]+\.[0-9]+'
