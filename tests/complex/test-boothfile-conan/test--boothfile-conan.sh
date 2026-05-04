#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Conan Installation
#
# Verifies that a Boothfile with `setup conan` correctly installs the Conan
# C/C++ package manager binary.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Conan Installation ==="

FAILED=0

# Test 1: conan is installed
ACTUAL=$(run_coding_booth --silence-build -- conan --version 2>/dev/null | head -1) || ACTUAL=""
if echo "$ACTUAL" | grep -qE "Conan version"; then
    print_test_result "true" "$0" "1" "Conan is installed"
else
    print_test_result "false" "$0" "1" "Conan should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: conan -h prints the command listing.
# Works for both Conan 1.x and 2.x — `conan config home` was removed in 2.x,
# and `conan profile detect` would require a compiler we deliberately don't
# install in this test. `conan -h` is a stable, no-side-effect probe.
ACTUAL=$(run_coding_booth --silence-build -- bash -c 'conan -h 2>&1' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -qiE "(commands|usage)"; then
    print_test_result "true" "$0" "2" "conan -h prints help"
else
    print_test_result "false" "$0" "2" "conan -h should print help"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
