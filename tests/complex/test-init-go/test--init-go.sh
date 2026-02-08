#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Init-generated Go workspace
#
# Verifies that a booth init generated Go Boothfile correctly installs Go
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Init-generated Go workspace ==="

FAILED=0

# Test 1: Go is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- go version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qE "go1\."; then
    print_test_result "true" "$0" "1" "Go is installed via init-generated Boothfile"
else
    print_test_result "false" "$0" "1" "Go should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: Go version matches requested (1.24.x)
if echo "$ACTUAL" | grep -qE "go1\.24"; then
    print_test_result "true" "$0" "2" "Go version is 1.24.x as specified"
else
    print_test_result "false" "$0" "2" "Go version should be 1.24.x"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
