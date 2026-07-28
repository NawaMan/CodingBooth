#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Roc Installation
#
# Verifies that a Boothfile with `setup roc --version latest` installs Roc and
# exposes the 'roc' binary on PATH.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Roc Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- roc --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qiE "roc"; then
    print_test_result "true" "$0" "1" "Roc is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Roc should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
