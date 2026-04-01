#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Conda Installation
#
# Verifies that a Boothfile with `setup conda` correctly installs Conda
# (Miniforge) and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Conda Installation ==="

FAILED=0

# Test 1: conda is installed and shows version
ACTUAL=$(run_coding_booth --silence-build -- conda --version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qE "conda"; then
    print_test_result "true" "$0" "1" "Conda is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Conda should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: python is available and shows Python 3
PYTHON_OUTPUT=$(run_coding_booth --silence-build -- python --version 2>/dev/null | head -1)

if echo "$PYTHON_OUTPUT" | grep -qE "Python 3"; then
    print_test_result "true" "$0" "2" "Python 3 is available via Conda"
else
    print_test_result "false" "$0" "2" "Python 3 should be available via Conda"
    echo "  Actual output: $PYTHON_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
