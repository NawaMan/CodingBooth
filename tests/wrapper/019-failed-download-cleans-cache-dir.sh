#!/usr/bin/env bash
# 019 — a download that fails must not leave an empty versions/<version>/ behind.
#
# DownloadBooth creates the shared-cache version dir before it touches the
# network, so every failure after that point used to litter the cache with an
# empty directory. Installing a version that does not exist 404s on the sha256
# fetch — the first network step after the dir is created — so it exercises that
# path without needing the network to be down.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
echo "=== INSTALL ==="
./booth install 0.0.0-does-not-exist 2>&1 || true
echo "=== CACHE ==="
ls -A ~/.cache/codingbooth/versions 2>/dev/null || echo "(no versions dir)"
BASH
)

# The install itself is expected to fail, at the sha256 fetch.
assert_contains "$LAST_OUTPUT" "FAILED (sha256 fetch)"

# ...and must leave nothing named after the version it could not fetch.
cache="${LAST_OUTPUT##*=== CACHE ===}"
assert_not_contains "$cache" "0.0.0-does-not-exist"
pass
