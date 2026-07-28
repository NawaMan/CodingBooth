#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Helm Installation
#
# Verifies that a Boothfile with `setup helm` correctly installs Helm
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Helm Installation ==="

FAILED=0

# Test 1: helm is installed and version is accessible
ACTUAL=$(run_coding_booth --silence-build -- helm version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "Version"; then
    print_test_result "true" "$0" "1" "Helm is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Helm should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: helm help is available
HELP_OUTPUT=$(run_coding_booth --silence-build -- helm help 2>&1) || true

if echo "$HELP_OUTPUT" | grep -qE "install"; then
    print_test_result "true" "$0" "2" "Helm help mentions install command"
else
    print_test_result "false" "$0" "2" "Helm help should contain 'install'"
    echo "  Actual output: $HELP_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
