#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile AWS CDK Installation
#
# Verifies that a Boothfile with `setup nodejs` and `setup aws-cdk` correctly
# installs AWS CDK CLI and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile AWS CDK Installation ==="

FAILED=0

# Test 1: CDK is installed and shows a version number
ACTUAL=$(run_coding_booth --silence-build -- cdk --version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qE "[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "AWS CDK is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "AWS CDK should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: CDK help includes synth or deploy commands
HELP_OUTPUT=$(run_coding_booth --silence-build -- cdk --help 2>&1) || true

if echo "$HELP_OUTPUT" | grep -qE "synth|deploy"; then
    print_test_result "true" "$0" "2" "AWS CDK help includes synth/deploy commands"
else
    print_test_result "false" "$0" "2" "AWS CDK help should include synth/deploy commands"
    echo "  Actual output: $HELP_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
