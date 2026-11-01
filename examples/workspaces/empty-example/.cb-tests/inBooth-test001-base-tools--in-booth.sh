#!/bin/bash
set -euo pipefail
# the base variant's own tools (just, git) exist, shell history is kept, project has README
echo "=== Testing base tools ==="
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
just --version
git --version
# config.toml's cache-files: each history file is kept in .booth/cache via a file-sync mount
grep -q "file-sync/home/coder/.bash_history " /proc/mounts
grep -q "file-sync/home/coder/.zsh_history " /proc/mounts
test -f README.md
