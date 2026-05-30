#!/usr/bin/env bash
# Build the booth-wrapper test image.
# Usage: tests/wrapper/build.sh [--no-cache]
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${BOOTH_TEST_IMAGE:-booth-wrapper-test}"

docker build \
    -t "$IMAGE" \
    -f "$SCRIPT_DIR/dockerfile" \
    "$@" \
    "$SCRIPT_DIR"

echo ""
echo "Built: $IMAGE"
echo "Run:   $SCRIPT_DIR/run.sh"
