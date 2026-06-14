#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Herdr Installation
#
# Verifies that `setup herdr` installs the Herdr agent multiplexer binary.
# `herdr --version` (or --help) should succeed and identify the tool.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Herdr Installation ==="

FAILED=0

# herdr --version or --help both work for a basic presence check.
ACTUAL=$(run_coding_booth --silence-build -- herdr --version 2>/dev/null || run_coding_booth --silence-build -- herdr --help 2>/dev/null | head -1) || true

if echo "$ACTUAL" | grep -qiE "herdr|agent|multiplexer"; then
    print_test_result "true" "$0" "1" "herdr is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "herdr should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
