#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Julia Installation
#
# Verifies that a Boothfile with `setup julia 1.11.3` correctly installs Julia
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Julia Installation ==="

FAILED=0

# Test 1: Julia is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- julia --version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qE "julia version"; then
    print_test_result "true" "$0" "1" "Julia is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Julia should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
