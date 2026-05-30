#!/usr/bin/env bash
# 040 — ./booth list inside a fresh DinD container reports no booth containers.
#       Exercises: install → run-mode dispatch → binary → docker query.
DIND=1
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
./booth list
BASH
)

assert_contains "$LAST_OUTPUT" "No booth containers found."
pass
