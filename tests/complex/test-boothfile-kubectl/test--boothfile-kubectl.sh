#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile kubectl Installation
#
# Verifies that a Boothfile with `setup kubectl` correctly installs kubectl
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile kubectl Installation ==="

FAILED=0

# Test 1: kubectl is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- kubectl version --client 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "Client Version"; then
    print_test_result "true" "$0" "1" "kubectl is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "kubectl should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: kubectl help is available
HELP_OUTPUT=$(run_coding_booth --silence-build -- kubectl help 2>/dev/null)
HELP_OUTPUT=$(printf '%s\n' "$HELP_OUTPUT" | head -5)

if echo "$HELP_OUTPUT" | grep -qE "kubectl"; then
    print_test_result "true" "$0" "2" "kubectl help is available"
else
    print_test_result "false" "$0" "2" "kubectl help should contain 'kubectl'"
    echo "  Actual output: $HELP_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
