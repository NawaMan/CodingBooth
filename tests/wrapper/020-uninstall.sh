#!/usr/bin/env bash
# 020 — ./booth uninstall -y removes .booth/tools/ contents (lock + binary).
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
echo "BEFORE:"
ls .booth/tools/ 2>/dev/null || echo "(none)"
./booth uninstall -y
echo "AFTER:"
ls .booth/tools/ 2>/dev/null || echo "(none)"
BASH
)

# Before: lock file and sha file are present.
before="${LAST_OUTPUT#*BEFORE:}"; before="${before%%AFTER:*}"
assert_contains "$before" "codingbooth.lock"

# After: tools dir should be empty / removed.
after="${LAST_OUTPUT##*AFTER:}"
assert_contains "$after" "(none)"
assert_contains "$LAST_OUTPUT" "Removed project binary association"
pass
