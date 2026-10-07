#!/usr/bin/env bash
# 061 — the binary treats a leading flag (`./booth --variant x`) as a run, so
#       the nested-booth guard must fire for it too, not only for bare `./booth`
#       and `./booth run`. -h/--help is help, not a run, and stays ungated.
#       The guard runs before any install, so no binary is needed here.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
cp /booth/booth ./booth

echo "=== NESTED FLAG-FIRST ==="
BOOTH_CONTAINER_NAME=fake ./booth --variant base 2>&1
echo "exit=$?"

echo "=== NESTED HELP (should be allowed) ==="
BOOTH_CONTAINER_NAME=fake ./booth --help 2>&1 || true
BASH
)

flag_first="${LAST_OUTPUT#*=== NESTED FLAG-FIRST ===}"; flag_first="${flag_first%%=== NESTED HELP*}"
nested_help="${LAST_OUTPUT##*=== NESTED HELP (should be allowed) ===}"

# A leading flag is a run — blocked.
assert_contains "$flag_first" "Running booth inside a booth container"
assert_contains "$flag_first" "exit=1"

# --help is not a run — no guard.
assert_not_contains "$nested_help" "Running booth inside a booth container"
pass
