#!/bin/bash
# Test: ts-node actually runs a TypeScript file, not just `--version`.
# `--version` kept passing while ts-node could run nothing at all: ts-node 10
# needs TypeScript's JavaScript API, which TypeScript 7 (the Go port) dropped.
# The Boothfile pins typescript@^5 for that; this catches the next such break.

set -euo pipefail

echo "=== Testing ts-node ==="
ts-node --version
cd "$(dirname "$0")/.."   # the project folder: /home/coder/code in a booth
output="$(ts-node hello.ts tester)"
echo "$output"
grep -q "Hello, tester!" <<< "$output"
