#!/usr/bin/env bash
# 093 — `install --cache` with no value is a usage error, not the ERR trap's
#       "Error on line N" from reading an unset $2 under set -u.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
cp /booth/booth ./booth
echo "=== RUN ==="
./booth install --cache 2>&1
echo "exit=$?"
ls .booth 2>/dev/null || echo "(no .booth)"
BASH
)

section="${LAST_OUTPUT##*=== RUN ===}"
assert_contains "$section" "--cache needs a value"
assert_not_contains "$section" "Error on line"
assert_contains "$section" "exit=1"
assert_contains "$section" "(no .booth)"
pass
