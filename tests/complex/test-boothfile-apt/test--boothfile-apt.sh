#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile `install apt` — no APT_SNAPSHOT
#
# Sanity-checks the `install apt` manager when APT_SNAPSHOT is unset: apt resolves
# against the live archive (no --snapshot). Verifies that:
#   1. apt is a recognized install manager (compiles to RUN apt--install.sh)
#   2. With nothing configured, the Dockerfile carries no APT_SNAPSHOT
#   3. The package actually installs in a real build (needs a local base image)
#
# Tests 1-2 are docker-free (emit-dockerfile only). Tests 3-4 build a real image
# and run only when a locally-rebuilt base image is present, because apt--install.sh
# is new and not yet baked into the Docker Hub base image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile install apt (no APT_SNAPSHOT) ==="

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

# Test 1: install apt compiles to RUN apt--install.sh (apt is a known manager)
if echo "$DOCKERFILE" | grep -qE "RUN apt--install\.sh jq" \
   && ! echo "$DOCKERFILE" | grep -q "Unknown install script 'apt'"; then
    print_test_result "true" "$0" "1" "install apt compiles to RUN apt--install.sh"
else
    print_test_result "false" "$0" "1" "install apt should compile to RUN apt--install.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# Test 2: with nothing configured, the Dockerfile carries no APT_SNAPSHOT
if ! echo "$DOCKERFILE" | grep -q "APT_SNAPSHOT"; then
    print_test_result "true" "$0" "2" "No APT_SNAPSHOT when none configured"
else
    print_test_result "false" "$0" "2" "Should not set APT_SNAPSHOT when none configured"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# The remaining tests build a real image, which needs apt--install.sh baked into the
# base image. That script is new and not yet on Docker Hub, so build against a
# locally-rebuilt base. Skip (reporting the emit results) when one isn't present.
use_local_base_image || exit $FAILED

# Test 3: the package actually installs (apt-get install runs in the build)
ACTUAL=$(run_coding_booth --silence-build -- jq --version 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if echo "$ACTUAL" | grep -qE "^jq-"; then
    print_test_result "true" "$0" "3" "install apt jq makes jq available"
else
    print_test_result "false" "$0" "3" "install apt jq should make jq available"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: apt registered the package (dpkg status confirms a real apt install)
ACTUAL=$(run_coding_booth --silence-build -- 'dpkg -s jq 2>/dev/null | grep -c "install ok installed"' 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "1" ]]; then
    print_test_result "true" "$0" "4" "jq is registered as installed by apt"
else
    print_test_result "false" "$0" "4" "jq should be registered as installed by apt"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
