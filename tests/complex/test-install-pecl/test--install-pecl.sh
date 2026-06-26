#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile `install pecl` sanity check
#
# Verifies that the pecl install manager is reachable end-to-end:
#   1. `install pecl redis` compiles to RUN pecl--install.sh (known manager)
#   2. The package actually installs in a real build
#
# Test 1 is docker-free (emit-dockerfile only). Test 2 builds a real image and
# runs only when a locally-rebuilt base image is present (cb-local/codingbooth),
# because some pecl--install.sh scripts are newer than the Docker Hub base.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile install pecl ==="

FAILED=0

# Locate the codingbooth binary for the docker-free emit-dockerfile check.
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

# Test 1: install pecl compiles to RUN pecl--install.sh (pecl is a known manager)
if echo "$DOCKERFILE" | grep -qE "RUN pecl--install\.sh" \
   && ! echo "$DOCKERFILE" | grep -q "Unknown install script 'pecl'"; then
    print_test_result "true" "$0" "1" "install pecl compiles to RUN pecl--install.sh"
else
    print_test_result "false" "$0" "1" "install pecl should compile to RUN pecl--install.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# The real build needs pecl--install.sh baked into the base image. Build against a
# locally-rebuilt base; skip (reporting the emit result) when one isn't present.
use_local_base_image || exit $FAILED

# Test 2: the package actually installs and is usable
ACTUAL=$(run_coding_booth --silence-build -- bash -lc 'php -m 2>/dev/null | grep -i redis' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -qE 'redis'; then
    print_test_result "true" "$0" "2" "redis extension is loaded"
else
    print_test_result "false" "$0" "2" "redis extension is loaded"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
