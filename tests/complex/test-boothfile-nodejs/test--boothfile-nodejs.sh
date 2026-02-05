#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Node.js Installation
#
# Verifies that a Boothfile with `setup nodejs 20` correctly installs Node.js
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Node.js Installation ==="

FAILED=0

# Test 1: Node.js is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- node --version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qE "v[0-9]+\."; then
    print_test_result "true" "$0" "1" "Node.js is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Node.js should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: Node.js version matches requested (v20.x)
if echo "$ACTUAL" | grep -qE "v20\."; then
    print_test_result "true" "$0" "2" "Node.js version is v20.x as specified"
else
    print_test_result "false" "$0" "2" "Node.js version should be v20.x"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: npm is also available
NPM_OUTPUT=$(run_coding_booth --silence-build -- npm --version 2>/dev/null | head -1) || true

if echo "$NPM_OUTPUT" | grep -qE "^[0-9]+\."; then
    print_test_result "true" "$0" "3" "npm is available with Node.js"
else
    print_test_result "false" "$0" "3" "npm should be available"
    echo "  Actual output: $NPM_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
