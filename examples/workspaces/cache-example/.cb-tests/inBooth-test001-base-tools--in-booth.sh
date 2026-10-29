#!/bin/bash
set -euo pipefail
# Checks base tools and that files under $HOME (what cache-files/cache-dirs persist) can be written and read.
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
echo "=== Testing cache example basics ==="
bash --version | head -1
git --version
just --version
test -f README.md
d="$HOME/.my_app_data"
mkdir -p "$d"
echo "important notes" > "$d/notes.txt"
grep -q 'important notes' "$d/notes.txt"
rm -f "$d/notes.txt"
echo "PASS"
