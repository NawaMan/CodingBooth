#!/bin/bash
set -euo pipefail
# base tools (just, git) exist, i3 is installed, project has README
echo "=== Testing base tools ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
just --version
git --version
command -v i3
test -f README.md
