#!/usr/bin/env bash
# 060 — running `./booth` (which dispatches as `run`) with BOOTH_CONTAINER_NAME
#       set must trigger the nested-booth guard: ASCII error box, exit 1.
#       Other commands (e.g. `list`) inside a booth container are not gated.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null

echo "=== NESTED RUN ==="
set +e
BOOTH_CONTAINER_NAME=fake ./booth 2>&1
echo "exit=$?"
set -e

echo "=== NESTED LIST (should be allowed) ==="
set +e
BOOTH_CONTAINER_NAME=fake ./booth list 2>&1 || true
set -e
BASH
)

nested_run="${LAST_OUTPUT#*=== NESTED RUN ===}"; nested_run="${nested_run%%=== NESTED LIST*}"
nested_list="${LAST_OUTPUT##*=== NESTED LIST (should be allowed) ===}"

# Nested `run` is blocked.
assert_contains "$nested_run" "Running booth inside a booth container"
assert_contains "$nested_run" "BOOTH_IN_BOOTH=true"
assert_contains "$nested_run" "exit=1"

# Nested `list` doesn't trip the guard — no ASCII box.
assert_not_contains "$nested_list" "Running booth inside a booth container"
pass
