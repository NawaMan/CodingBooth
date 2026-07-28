#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Azure CLI Installation
#
# Verifies that a Boothfile with `setup azure-cli` correctly installs the
# Azure CLI and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Azure CLI Installation ==="

FAILED=0

# Test 1: az --version output contains "azure-cli"
ACTUAL=$(run_coding_booth --silence-build -- az --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -5)

if echo "$ACTUAL" | grep -qi "azure-cli"; then
    print_test_result "true" "$0" "1" "Azure CLI is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Azure CLI should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: az help output contains subcommands
HELP_OUTPUT=$(run_coding_booth --silence-build -- az help 2>/dev/null) || true
HELP_OUTPUT=$(printf '%s\n' "$HELP_OUTPUT" | head -20)

if echo "$HELP_OUTPUT" | grep -qiE "group|Commands"; then
    print_test_result "true" "$0" "2" "Azure CLI subcommands are available"
else
    print_test_result "false" "$0" "2" "Azure CLI subcommands should be available"
    echo "  Actual output: $HELP_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
