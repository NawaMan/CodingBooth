#!/bin/bash
set -euo pipefail
# `just build` builds the game, and the binary plays a game by itself.
cd "$(dirname "$0")/.."
echo "=== just build ==="
rm -rf bin
just build
test -x bin/go4096
out="$(bin/go4096 --demo)"
echo "$out" | tail -1
grep -q '^demo: seed 1, [0-9]* moves, score [0-9]*, best tile [0-9]*$' <<< "$out"
