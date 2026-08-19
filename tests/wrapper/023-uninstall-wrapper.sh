#!/usr/bin/env bash
# 023 — `booth uninstall --wrapper -y` deletes ./booth itself, and the script
#       survives its own deletion long enough to finish. The wrapper unlinks
#       the file it is still executing; bash keeps reading through the open fd,
#       so the trailing output must still appear. Asserting the LAST line is
#       the point — a truncated run would drop it silently and still exit 0.
#       Also guards the scope boundary: --wrapper alone must not touch the
#       shared cache.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null

# Read the pinned version before uninstall removes the lock file.
version=$(grep '^version=' .booth/tools/codingbooth.lock | cut -d= -f2)

echo "=== BEFORE ==="
[[ -f ./booth ]] && echo "WRAPPER: present" || echo "WRAPPER: MISSING (test setup failed)"
[[ -d ~/.cache/codingbooth/versions/$version ]] \
    && echo "CACHE_DIR: present" || echo "CACHE_DIR: MISSING (test setup failed)"

./booth uninstall --wrapper -y; rc=$?
echo "EXIT: $rc"

echo "=== AFTER ==="
[[ -f ./booth ]] && echo "WRAPPER: still present (regression!)" || echo "WRAPPER: gone"
[[ -d ~/.cache/codingbooth/versions/$version ]] \
    && echo "CACHE_DIR: kept" || echo "CACHE_DIR: gone (regression! --wrapper must not clean the cache)"
BASH
)

# Trim on the AFTER banner, not on the uninstall command line — the heredoc is
# never echoed, so a `%%./booth uninstall*` trim matches nothing and silently
# leaves the AFTER section inside `before`.
before="${LAST_OUTPUT#*=== BEFORE ===}"; before="${before%%=== AFTER ===*}"
after="${LAST_OUTPUT##*=== AFTER ===}"

assert_contains "$before" "WRAPPER: present"
assert_contains "$before" "CACHE_DIR: present"

assert_contains "$LAST_OUTPUT" "Removed wrapper:"
assert_contains "$LAST_OUTPUT" "EXIT: 0"

# The self-delete happens before this line is printed — if bash lost the
# script mid-run, the message would never arrive.
assert_contains "$LAST_OUTPUT" "CodingBooth has been uninstalled from this project."

# No shared-binary scope was requested, so the cache hint must be offered.
assert_contains "$LAST_OUTPUT" "To clean shared cache"

assert_contains "$after" "WRAPPER: gone"
assert_contains "$after" "CACHE_DIR: kept"
pass
