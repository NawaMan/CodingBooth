#!/usr/bin/env bash
# 021 — `booth uninstall --shared-binary -y` removes the version-specific cache
#       directory. Regression guard for the inlined `rm -rf` that replaced the
#       old `ToolsCacheClean` call inside UninstallBooth.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
./booth install >/dev/null
version=$(grep '^version=' .booth/tools/codingbooth.lock | cut -d= -f2)
echo "VERSION: $version"

echo "=== BEFORE ==="
if [[ -d ~/.cache/codingbooth/versions/$version ]]; then
    echo "CACHE_DIR: present"
else
    echo "CACHE_DIR: MISSING (test setup failed)"
fi

./booth uninstall --shared-binary -y

echo "=== AFTER ==="
if [[ -d ~/.cache/codingbooth/versions/$version ]]; then
    echo "CACHE_DIR: still present (regression!)"
else
    echo "CACHE_DIR: gone"
fi
BASH
)

# Trim on the AFTER banner: the heredoc is never echoed, so trimming at
# `./booth uninstall` matched nothing and left the AFTER section inside
# `before` — the scoping this line claims to do was never happening.
before="${LAST_OUTPUT#*=== BEFORE ===}"; before="${before%%=== AFTER ===*}"
after="${LAST_OUTPUT##*=== AFTER ===}"

assert_contains "$before" "CACHE_DIR: present"
assert_contains "$LAST_OUTPUT" "Removed cached version"
assert_contains "$after" "CACHE_DIR: gone"
pass
