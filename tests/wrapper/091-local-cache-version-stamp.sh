#!/usr/bin/env bash
# 091 — a --cache=local binary only counts when its version stamp matches the
#       lock. The binary's file name is the same for every version and it still
#       matches its own checksum, so before the stamp a lock bumped by `git pull`
#       kept running the old binary. Covers a wrong stamp and a missing one (an
#       install made before the stamp existed); both must re-download.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
cp /booth/booth ./booth
./booth install --cache=local >/dev/null
version=$(grep '^version=' .booth/tools/codingbooth.lock | cut -d= -f2)
echo "=== STAMP AFTER INSTALL ==="
[[ "$(cat .booth/tools/codingbooth-version)" == "$version" ]] && echo "stamp=lock" || echo "stamp!=lock"

echo "0.0.0-stale" > .booth/tools/codingbooth-version
echo "=== WRONG STAMP ==="
./booth tools-cache list 2>&1
echo "exit=$?"
[[ "$(cat .booth/tools/codingbooth-version)" == "$version" ]] && echo "stamp=lock" || echo "stamp!=lock"

rm -f .booth/tools/codingbooth-version
echo "=== NO STAMP ==="
./booth tools-cache list 2>&1
echo "exit=$?"
[[ "$(cat .booth/tools/codingbooth-version 2>/dev/null)" == "$version" ]] && echo "stamp=lock" || echo "stamp!=lock"

echo "=== SHARED CACHE ==="
ls ~/.cache/codingbooth/versions/ 2>/dev/null || echo "(none)"
BASH
)

installed="${LAST_OUTPUT#*=== STAMP AFTER INSTALL ===}"; installed="${installed%%=== WRONG STAMP*}"
assert_contains "$installed" "stamp=lock"

wrong="${LAST_OUTPUT#*=== WRONG STAMP ===}"; wrong="${wrong%%=== NO STAMP*}"
assert_contains "$wrong" "Binary missing, downloading version"
assert_contains "$wrong" "exit=0"
assert_contains "$wrong" "stamp=lock"

none="${LAST_OUTPUT#*=== NO STAMP ===}"; none="${none%%=== SHARED CACHE*}"
assert_contains "$none" "Binary missing, downloading version"
assert_contains "$none" "exit=0"
assert_contains "$none" "stamp=lock"

# Re-downloads stay in local mode.
assert_contains "${LAST_OUTPUT##*=== SHARED CACHE ===}" "(none)"
pass
