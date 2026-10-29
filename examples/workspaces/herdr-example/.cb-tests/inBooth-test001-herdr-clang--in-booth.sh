#!/bin/bash
set -euo pipefail
# Herdr, Claude Code and clang 18 are installed; clang++ compiles and runs a program.
echo "=== Testing Herdr and clang ==="
command -v herdr
herdr --version || herdr --help >/dev/null
claude --version
clang --version | grep -q "version 18"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '#include <iostream>\nint main(){std::cout<<"hello from clang\\n";}\n' > "$tmp/h.cpp"
clang++ "$tmp/h.cpp" -o "$tmp/h"
"$tmp/h" | grep -q "hello from clang"
