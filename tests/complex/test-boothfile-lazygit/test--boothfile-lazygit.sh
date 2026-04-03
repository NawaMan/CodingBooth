#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile lazygit Installation
#
# Verifies that a Boothfile with `setup lazygit` correctly installs lazygit
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile lazygit Installation ==="

FAILED=0

# Test 1: lazygit is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- lazygit --version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qE "version="; then
    print_test_result "true" "$0" "1" "lazygit is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "lazygit should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
