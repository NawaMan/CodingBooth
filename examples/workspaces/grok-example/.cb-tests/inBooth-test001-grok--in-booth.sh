#!/bin/bash
set -euo pipefail
# Checks the grok CLI is installed (no login).
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing grok ==="
command -v grok
grok --version | grep -qi 'grok'
echo "PASS"
