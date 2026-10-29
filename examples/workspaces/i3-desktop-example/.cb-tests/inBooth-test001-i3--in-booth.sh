#!/bin/bash
set -euo pipefail
# i3 binaries are installed and print a version (no display needed)
echo "=== Testing i3 ==="
command -v i3
i3 --version | grep -qi "i3 version"
command -v i3-msg
