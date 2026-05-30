#!/usr/bin/env bash
# 050 — install --cache=local puts the binary inside .booth/tools/ and adds
#       a tools/codingbooth-* line to the local .gitignore.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install --cache=local
echo "=== TOOLS DIR ==="
ls .booth/tools/
echo "=== LOCK FILE ==="
cat .booth/tools/codingbooth.lock
echo "=== GITIGNORE ==="
cat .booth/.gitignore
echo "=== SHARED CACHE STATE ==="
ls ~/.cache/codingbooth/versions/ 2>/dev/null || echo "(none)"
BASH
)

tools_section="${LAST_OUTPUT#*=== TOOLS DIR ===}"; tools_section="${tools_section%%=== LOCK FILE*}"
assert_contains "$tools_section" "codingbooth-"
assert_contains "$tools_section" "codingbooth.sha256"
assert_contains "$tools_section" "codingbooth.lock"

lock_section="${LAST_OUTPUT#*=== LOCK FILE ===}"; lock_section="${lock_section%%=== GITIGNORE*}"
assert_contains "$lock_section" "cache=local"

gitignore_section="${LAST_OUTPUT#*=== GITIGNORE ===}"; gitignore_section="${gitignore_section%%=== SHARED CACHE*}"
assert_contains "$gitignore_section" "tools/codingbooth-"
assert_contains "$gitignore_section" "tools/*.sha256"

# Shared cache should be untouched (no versions dir created).
shared_section="${LAST_OUTPUT##*=== SHARED CACHE STATE ===}"
assert_contains "$shared_section" "(none)"
pass
