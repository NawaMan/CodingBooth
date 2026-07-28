#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile .NET Installation
#
# Verifies that a Boothfile with `setup dotnet` correctly installs the .NET SDK
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile .NET Installation ==="

FAILED=0

# Test 1: dotnet is installed and shows a version number
ACTUAL=$(run_coding_booth --silence-build -- dotnet --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" ".NET SDK is installed via Boothfile"
else
    print_test_result "false" "$0" "1" ".NET SDK should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: dotnet --list-sdks shows installed SDKs
SDK_OUTPUT=$(run_coding_booth --silence-build -- dotnet --list-sdks 2>/dev/null) || true

if echo "$SDK_OUTPUT" | grep -qE "[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "2" ".NET SDK list shows installed SDKs"
else
    print_test_result "false" "$0" "2" ".NET SDK list should show installed SDKs"
    echo "  Actual output: $SDK_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
