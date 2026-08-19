#!/usr/bin/env bash
# 024 — `booth uninstall --all -y` is the union of --all-shared-binary and
#       --wrapper: project association, every cached version, and ./booth all
#       go in one run. Guards the flag-expansion in UninstallBooth — a scope
#       dropped from --all would leave one of the three behind while still
#       reporting success.
#
#       --all does NOT include shell-config (user-scoped, other projects may
#       use it); that boundary is covered by 030-shell-config.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
# Two versions in the shared cache so "all" is distinguishable from "pinned".
./booth install 0.52.0 >/dev/null
./booth install 0.53.0 >/dev/null

echo "=== BEFORE ==="
[[ -f ./booth ]] && echo "WRAPPER: present" || echo "WRAPPER: MISSING (test setup failed)"
echo "CACHED: $(ls ~/.cache/codingbooth/versions/ | tr '\n' ' ')"
ls .booth/tools/

./booth uninstall --all -y; rc=$?
echo "EXIT: $rc"

echo "=== AFTER ==="
[[ -f ./booth ]] && echo "WRAPPER: still present (regression!)" || echo "WRAPPER: gone"
[[ -d ~/.cache/codingbooth/versions ]] && echo "versions/ STILL EXISTS" || echo "versions/ GONE"
[[ -d .booth/tools ]] && echo "TOOLS_DIR: still present (regression!)" || echo "TOOLS_DIR: gone"
BASH
)

# Trim on the AFTER banner, not on the uninstall command line — the heredoc is
# never echoed, so a `%%./booth uninstall*` trim matches nothing and silently
# leaves the AFTER section inside `before`.
before="${LAST_OUTPUT#*=== BEFORE ===}"; before="${before%%=== AFTER ===*}"
after="${LAST_OUTPUT##*=== AFTER ===}"

assert_contains "$before" "WRAPPER: present"
assert_contains "$before" "0.52.0"
assert_contains "$before" "0.53.0"
assert_contains "$before" "codingbooth.lock"

# All three scopes must report — one missing line means a scope was dropped.
assert_contains "$LAST_OUTPUT" "Removed project binary association"
assert_contains "$LAST_OUTPUT" "Removed all cached versions"
assert_contains "$LAST_OUTPUT" "Removed wrapper:"
assert_contains "$LAST_OUTPUT" "EXIT: 0"
assert_contains "$LAST_OUTPUT" "CodingBooth has been uninstalled from this project."

# The cache was cleaned, so the "go clean your cache" hint must be suppressed.
assert_not_contains "$LAST_OUTPUT" "To clean shared cache"

assert_contains "$after" "WRAPPER: gone"
assert_contains "$after" "versions/ GONE"
assert_contains "$after" "TOOLS_DIR: gone"
pass
