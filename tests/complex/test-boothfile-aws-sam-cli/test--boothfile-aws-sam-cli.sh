#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile AWS SAM CLI Installation
#
# Verifies that a Boothfile with `setup aws-sam-cli` correctly installs
# AWS SAM CLI and the booth starts without errors.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile AWS SAM CLI Installation ==="

FAILED=0

# Test 1: SAM CLI is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- sam --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "SAM CLI"; then
    print_test_result "true" "$0" "1" "AWS SAM CLI is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "AWS SAM CLI should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
