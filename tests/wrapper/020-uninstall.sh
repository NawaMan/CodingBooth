#!/usr/bin/env bash
# 020 — ./booth uninstall -y removes .booth/tools/ contents (lock + binary),
#       and the shared-cache advice it prints still works with the lock gone.
#       It used to suggest `tools-cache clean`, which the binary handles — and
#       the binary is unreachable once the lock has been removed.
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
echo "=== ADVICE ==="
./booth uninstall --all-shared-binary -y >/dev/null
ls ~/.cache/codingbooth/versions 2>/dev/null || echo "(cache gone)"
BASH
)

# Before: lock file and sha file are present.
before="${LAST_OUTPUT#*BEFORE:}"; before="${before%%AFTER:*}"
assert_contains "$before" "codingbooth.lock"

# After: tools dir should be empty / removed.
after="${LAST_OUTPUT##*AFTER:}"; after="${after%%=== ADVICE ===*}"
assert_contains "$after" "(none)"
assert_contains "$LAST_OUTPUT" "Removed project binary association"

# The advice names a command that works here, and following it clears the cache.
uninstall_out="${LAST_OUTPUT%%AFTER:*}"
assert_contains "$uninstall_out" "uninstall --all-shared-binary -y"
assert_not_contains "$uninstall_out" "tools-cache clean"
assert_contains "${LAST_OUTPUT##*=== ADVICE ===}" "(cache gone)"
pass
