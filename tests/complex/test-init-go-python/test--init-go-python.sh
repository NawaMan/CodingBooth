#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Init-generated Go + Python workspace
#
# Verifies that a booth init generated multi-template Boothfile correctly
# installs both Go and Python in the same container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Init-generated Go + Python workspace ==="

FAILED=0

# Test 1: Go is installed
GO_ACTUAL=$(run_coding_booth --silence-build -- go version 2>/dev/null | head -1)

if echo "$GO_ACTUAL" | grep -qE "go1\.24"; then
    print_test_result "true" "$0" "1" "Go 1.24 is installed"
else
    print_test_result "false" "$0" "1" "Go 1.24 should be installed"
    echo "  Actual output: $GO_ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: Python is installed
PY_ACTUAL=$(run_coding_booth --silence-build -- python3 --version 2>/dev/null | head -1)

if echo "$PY_ACTUAL" | grep -qE "Python 3\.12"; then
    print_test_result "true" "$0" "2" "Python 3.12 is installed"
else
    print_test_result "false" "$0" "2" "Python 3.12 should be installed"
    echo "  Actual output: $PY_ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: Both tools coexist (run in single session)
BOTH=$(run_coding_booth --silence-build -- bash -c 'go version && python3 --version' 2>/dev/null)

if echo "$BOTH" | grep -qE "go1\." && echo "$BOTH" | grep -qE "Python 3\."; then
    print_test_result "true" "$0" "3" "Go and Python coexist in same container"
else
    print_test_result "false" "$0" "3" "Both Go and Python should be available"
    echo "  Actual output: $BOTH"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
