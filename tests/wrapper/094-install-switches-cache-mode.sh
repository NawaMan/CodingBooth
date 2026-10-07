#!/usr/bin/env bash
# 094 — `install --cache=<mode>` on an installed project switches to that mode,
#       keeping the locked version. It used to find the binary in the lock's
#       mode and stop at "already installed", ignoring the flag. The binary in
#       the old location is kept, so switching back to local reuses it.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
cp /booth/booth ./booth
./booth install >/dev/null
version=$(grep '^version=' .booth/tools/codingbooth.lock | cut -d= -f2)

echo "=== TO LOCAL ==="
./booth install --cache=local 2>&1
echo "exit=$?"
grep '^cache=' .booth/tools/codingbooth.lock
[[ "$(grep '^version=' .booth/tools/codingbooth.lock | cut -d= -f2)" == "$version" ]] && echo "version=kept" || echo "version=changed"
[[ "$(cat .booth/tools/codingbooth-version 2>/dev/null)" == "$version" ]] && echo "stamp=lock" || echo "stamp!=lock"

echo "=== TO SHARED ==="
./booth install --cache=shared 2>&1
echo "exit=$?"
grep '^cache=' .booth/tools/codingbooth.lock
[[ "$(grep '^version=' .booth/tools/codingbooth.lock | cut -d= -f2)" == "$version" ]] && echo "version=kept" || echo "version=changed"
ls .booth/tools/codingbooth-linux-* >/dev/null 2>&1 && echo "local-binary=kept" || echo "local-binary=gone"
./booth version 2>&1 | grep '^Cache mode:'

echo "=== BACK TO LOCAL ==="
./booth install --cache=local 2>&1
echo "exit=$?"
grep '^cache=' .booth/tools/codingbooth.lock

echo "=== SAME MODE ==="
./booth install --cache=local 2>&1
echo "exit=$?"
BASH
)

to_local="${LAST_OUTPUT#*=== TO LOCAL ===}"; to_local="${to_local%%=== TO SHARED*}"
assert_contains "$to_local" "Switching cache mode from shared to local"
assert_contains "$to_local" "exit=0"
assert_contains "$to_local" "cache=local"
assert_contains "$to_local" "version=kept"
assert_contains "$to_local" "stamp=lock"

to_shared="${LAST_OUTPUT#*=== TO SHARED ===}"; to_shared="${to_shared%%=== BACK TO LOCAL*}"
assert_contains "$to_shared" "Switching cache mode from local to shared"
assert_contains "$to_shared" "exit=0"
assert_contains "$to_shared" "cache=shared"
assert_contains "$to_shared" "version=kept"
assert_contains "$to_shared" "local-binary=kept"
assert_contains "$to_shared" "Cache mode: shared"

# The kept local binary is reused, not downloaded again.
back="${LAST_OUTPUT#*=== BACK TO LOCAL ===}"; back="${back%%=== SAME MODE*}"
assert_contains "$back" "already up-to-date"
assert_not_contains "$back" "Downloading"
assert_contains "$back" "cache=local"

# Asking for the mode the project already has is still a no-op.
same="${LAST_OUTPUT##*=== SAME MODE ===}"
assert_contains "$same" "already installed"
assert_contains "$same" "exit=0"
pass
