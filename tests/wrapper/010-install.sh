#!/usr/bin/env bash
# 010 — ./booth install downloads the binary, writes lock file, gitignore.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install
echo "---"
ls .booth/tools/
echo "---"
cat .booth/tools/codingbooth.lock
echo "---"
ls .booth/.gitignore
BASH
)

assert_contains "$LAST_OUTPUT" "CodingBooth installed:"
assert_contains "$LAST_OUTPUT" "codingbooth.lock"
assert_contains "$LAST_OUTPUT" "version="
assert_contains "$LAST_OUTPUT" "cache=shared"
assert_contains "$LAST_OUTPUT" ".booth/.gitignore"
pass
