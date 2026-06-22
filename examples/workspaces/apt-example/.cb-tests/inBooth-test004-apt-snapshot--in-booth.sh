#!/bin/bash
# Test: APT_SNAPSHOT was baked into the image.
# The `env APT_SNAPSHOT=...` line in the Boothfile becomes a Dockerfile ENV, so the
# value persists into the running booth — and at build time it pinned every apt
# resolution to that archive snapshot.

set -euo pipefail

echo "=== Testing APT_SNAPSHOT freeze ==="
EXPECTED="20250601T000000Z"
ACTUAL="$(printenv APT_SNAPSHOT || true)"
echo "APT_SNAPSHOT=${ACTUAL}"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    echo "OK: archive frozen to snapshot ${EXPECTED}"
else
    echo "FAIL: expected APT_SNAPSHOT=${EXPECTED}, got '${ACTUAL}'"
    exit 1
fi
