#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Terraform Installation
#
# Verifies that a Boothfile with `setup terraform` correctly installs Terraform
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Terraform Installation ==="

FAILED=0

# Test 1: Terraform is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- terraform --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "Terraform v"; then
    print_test_result "true" "$0" "1" "Terraform is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Terraform should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: Terraform help shows subcommands (plan)
HELP_OUTPUT=$(run_coding_booth --silence-build -- terraform -help 2>&1) || true

if echo "$HELP_OUTPUT" | grep -q "plan"; then
    print_test_result "true" "$0" "2" "Terraform help includes plan subcommand"
else
    print_test_result "false" "$0" "2" "Terraform help should include plan subcommand"
    echo "  Actual output: $HELP_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
