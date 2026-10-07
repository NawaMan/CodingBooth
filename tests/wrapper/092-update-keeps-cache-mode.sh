#!/usr/bin/env bash
# 092 — `update` / `install` without --cache keep the project's cache mode.
#       They used to default to shared, so a plain `update` in a --cache=local
#       project wrote cache=shared to the lock while the old local binary kept
#       winning the lookup.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
cp /booth/booth ./booth
./booth install --cache=local >/dev/null
./booth update >/dev/null 2>&1
echo "update-exit=$?"
echo "=== LOCK ==="
grep '^cache=' .booth/tools/codingbooth.lock
echo "=== SHARED CACHE ==="
ls ~/.cache/codingbooth/versions/ 2>/dev/null || echo "(none)"
BASH
)

assert_contains "$LAST_OUTPUT" "update-exit=0"
lock="${LAST_OUTPUT#*=== LOCK ===}"; lock="${lock%%=== SHARED CACHE*}"
assert_contains "$lock" "cache=local"
assert_contains "${LAST_OUTPUT##*=== SHARED CACHE ===}" "(none)"
pass
