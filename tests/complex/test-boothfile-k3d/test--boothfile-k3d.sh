#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile k3d Installation
#
# Verifies that a Boothfile with `setup k3d` installs the k3d binary.
# Does not create a cluster (that requires Docker / dind).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile k3d Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- k3d version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qiE "k3d version"; then
    print_test_result "true" "$0" "1" "k3d is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "k3d should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
