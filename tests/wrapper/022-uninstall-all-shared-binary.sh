#!/usr/bin/env bash
# 022 — `booth uninstall --all-shared-binary -y` removes the entire
#       `~/.cache/codingbooth/versions/` tree, not just the pinned version.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
# Populate the shared cache with two versions so we can verify both go.
./booth install 0.52.0 >/dev/null
./booth install 0.53.0 >/dev/null

echo "=== BEFORE ==="
ls ~/.cache/codingbooth/versions/

./booth uninstall --all-shared-binary -y

echo "=== AFTER ==="
if [[ -d ~/.cache/codingbooth/versions ]]; then
    echo "versions/ STILL EXISTS:"
    ls ~/.cache/codingbooth/versions/
else
    echo "versions/ GONE"
fi
BASH
)

before="${LAST_OUTPUT#*=== BEFORE ===}"; before="${before%%./booth uninstall*}"
after="${LAST_OUTPUT##*=== AFTER ===}"

assert_contains "$before" "0.52.0"
assert_contains "$before" "0.53.0"
assert_contains "$LAST_OUTPUT" "Removed all cached versions"
assert_contains "$after" "versions/ GONE"
pass
