#!/usr/bin/env bash
# 002 — ./booth version reports wrapper version + "not installed" state.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth version
BASH
)

assert_contains "$LAST_OUTPUT" "CodingBooth Wrapper:"
assert_contains "$LAST_OUTPUT" "CodingBooth: not installed"
assert_contains "$LAST_OUTPUT" "Platform:"
pass
