#!/bin/bash
set -euo pipefail
# The Snake project builds with zig build.
echo "=== Testing Snake build ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
zig build
