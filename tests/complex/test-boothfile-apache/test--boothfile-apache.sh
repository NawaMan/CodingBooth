#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Apache Installation
#
# Verifies that `setup apache` installs the Apache HTTP Server.
# `apache2 -v` prints "Server version: Apache/X.Y.Z (Ubuntu)" on the first line.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Apache Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- apache2 -v 2>/dev/null | head -1 || true)

if echo "$ACTUAL" | grep -qiE "apache[^0-9]*[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "Apache is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Apache should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
