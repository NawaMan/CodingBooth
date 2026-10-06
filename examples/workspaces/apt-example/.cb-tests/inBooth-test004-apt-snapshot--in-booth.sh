#!/bin/bash
# Test: APT_SNAPSHOT was baked into the image.
# The `env APT_SNAPSHOT=...` line in the Boothfile becomes a Dockerfile ENV, so the
# value persists into the running booth — and at build time it pinned every apt
# resolution to that archive snapshot.
#
# The expected value is read from the Boothfile itself, not written here: the
# date moves whenever the example's snapshot is bumped, and the test is about the
# line reaching the image, not about which date it holds.

set -euo pipefail

echo "=== Testing APT_SNAPSHOT freeze ==="
BOOTHFILE="/home/coder/code/.booth/Boothfile"
EXPECTED="$(sed -n 's/^env APT_SNAPSHOT=//p' "$BOOTHFILE" | head -1)"
ACTUAL="$(printenv APT_SNAPSHOT || true)"
echo "Boothfile: APT_SNAPSHOT=${EXPECTED}"
echo "Booth:     APT_SNAPSHOT=${ACTUAL}"

if [[ -z "$EXPECTED" ]]; then
    echo "FAIL: ${BOOTHFILE} has no 'env APT_SNAPSHOT=<id>' line — this example is meant to be frozen"
    exit 1
fi
if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    echo "OK: archive frozen to snapshot ${EXPECTED}"
else
    echo "FAIL: expected APT_SNAPSHOT=${EXPECTED} (from the Boothfile), got '${ACTUAL}'"
    exit 1
fi
