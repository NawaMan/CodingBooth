#!/usr/bin/env bash
# 013 — installing a specific cached version after another prints
#       "Switched from X to Y." Exercises the cache fast-path + switch message.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install 0.52.0 >/dev/null
./booth install 0.53.0 >/dev/null
echo "=== SWITCH BACK ==="
./booth install 0.52.0
BASH
)

assert_contains "$LAST_OUTPUT" "Switched from 0.53.0 to 0.52.0."
assert_contains "$LAST_OUTPUT" "already up-to-date"
pass
