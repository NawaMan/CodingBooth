#!/usr/bin/env bash
# 012 — after install, ./booth version reports both wrapper and binary version,
#       plus platform and cache info.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
./booth version
BASH
)

assert_contains "$LAST_OUTPUT" "CodingBooth Wrapper:"
assert_contains "$LAST_OUTPUT" "Platform:"
assert_contains "$LAST_OUTPUT" "Cache mode: shared"
assert_not_contains "$LAST_OUTPUT" "CodingBooth: not installed"
pass
