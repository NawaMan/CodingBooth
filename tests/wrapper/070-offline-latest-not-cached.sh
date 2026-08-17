#!/usr/bin/env bash
# 070 — with no network, `booth install` cannot learn what "latest" points to.
#
# The version fallback is right for a pinned version ("0.71.0" resolves to
# itself) but wrong for "latest", which is a moving alias. Letting it through
# would key the shared cache on versions/latest/ — a directory no real lock
# version ever matches — and write `version=latest` into the lock file, which
# pins nothing. Expect a clear error and nothing created.
NETWORK=none
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
echo "=== INSTALL ==="
./booth install 2>&1 || true
echo "=== CACHE ==="
ls -A ~/.cache/codingbooth/versions 2>/dev/null || echo "(no versions dir)"
BASH
)

assert_contains "$LAST_OUTPUT" "Could not resolve which version"

# Nothing cached at all — in particular no dir literally named "latest".
cache="${LAST_OUTPUT##*=== CACHE ===}"
assert_not_contains "$cache" "latest"
pass
