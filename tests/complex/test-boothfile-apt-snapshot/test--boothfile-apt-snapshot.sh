#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile `install apt` — with APT_SNAPSHOT
#
# Sanity-checks the `install apt` manager when APT_SNAPSHOT is set: apt is pinned to
# an Ubuntu archive snapshot (--snapshot) so the whole resolution is frozen. The
# Boothfile sets `env APT_SNAPSHOT=<id>` exactly as `booth config` would. Verifies:
#   1. The ENV APT_SNAPSHOT directive is emitted before the RUN apt--install.sh line
#      (so the script sees it at build time)
#   2. The package actually installs from the frozen snapshot in a real build
#
# Test 1 is docker-free (emit-dockerfile only). Tests 2-3 build a real image and run
# only when a locally-rebuilt base image is present, because apt--install.sh is new
# and not yet baked into the Docker Hub base image. The build also requires network
# access to snapshot.ubuntu.com.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

SNAPSHOT="20250601T000000Z"

echo "=== Test: Boothfile install apt (APT_SNAPSHOT=${SNAPSHOT}) ==="

FAILED=0

# Locate the codingbooth binary for the docker-free emit-dockerfile checks.
BOOTH_PATH=""
CHECK_DIR="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -f "$CHECK_DIR/codingbooth" && -x "$CHECK_DIR/codingbooth" ]]; then
        BOOTH_PATH="$CHECK_DIR/codingbooth"
        break
    fi
    CHECK_DIR="$(dirname "$CHECK_DIR")"
done
if [[ -z "$BOOTH_PATH" ]]; then
    echo "ERROR: Could not find codingbooth"
    exit 1
fi

DOCKERFILE=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" 2>&1) || true

# Test 1: ENV APT_SNAPSHOT is emitted before RUN apt--install.sh so the install
# script sees it at build time.
ENV_LINE=$(echo "$DOCKERFILE" | grep -n "ENV APT_SNAPSHOT=${SNAPSHOT}" | head -1 | cut -d: -f1)
RUN_LINE=$(echo "$DOCKERFILE" | grep -n "RUN apt--install\.sh jq" | head -1 | cut -d: -f1)
if [[ -n "$ENV_LINE" && -n "$RUN_LINE" && "$ENV_LINE" -lt "$RUN_LINE" ]]; then
    print_test_result "true" "$0" "1" "ENV APT_SNAPSHOT precedes RUN apt--install.sh"
else
    print_test_result "false" "$0" "1" "ENV APT_SNAPSHOT should precede RUN apt--install.sh"
    echo "  ENV_LINE=$ENV_LINE RUN_LINE=$RUN_LINE"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# The remaining tests build a real image, which needs apt--install.sh baked into the
# base image. That script is new and not yet on Docker Hub, so build against a
# locally-rebuilt base. Skip (reporting the emit result) when one isn't present.
use_local_base_image || exit $FAILED

# Test 2: the package installs from the frozen snapshot (build runs
# `apt-get install --snapshot <id>` and must succeed).
ACTUAL=$(run_coding_booth --silence-build -- jq --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -qE "^jq-"; then
    print_test_result "true" "$0" "2" "install apt jq makes jq available under snapshot pin"
else
    print_test_result "false" "$0" "2" "install apt jq should make jq available under snapshot pin"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: apt registered the package (dpkg status confirms a real apt install).
ACTUAL=$(run_coding_booth --silence-build -- 'dpkg -s jq 2>/dev/null | grep -c "install ok installed"' 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "1" ]]; then
    print_test_result "true" "$0" "3" "jq is registered as installed by apt"
else
    print_test_result "false" "$0" "3" "jq should be registered as installed by apt"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
