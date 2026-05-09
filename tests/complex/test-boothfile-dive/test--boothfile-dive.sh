#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile dive Installation
#
# Verifies that `setup dive` installs the dive binary.
# `dive --version` prints "dive X.Y.Z" and exits without needing Docker.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile dive Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- dive --version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qiE "dive[^0-9]*[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "dive is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "dive should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
