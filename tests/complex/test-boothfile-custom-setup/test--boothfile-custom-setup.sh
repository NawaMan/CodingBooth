#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Custom Setup Script
#
# Verifies that custom setup scripts in .booth/setups/ are correctly
# copied into the image and executed during build.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Custom Setup Script ==="

FAILED=0

# Test 1: The custom setup script ran (marker file exists)
# Use --silence-build to suppress build output, redirect stderr to /dev/null
MARKER=$(run_coding_booth --silence-build -- cat /tmp/mytool-marker.txt 2>/dev/null | tr -d '\r\n')

if [[ "$MARKER" == "MYTOOL_INSTALLED" ]]; then
    print_test_result "true" "$0" "1" "Custom setup script executed during build"
else
    print_test_result "false" "$0" "1" "Custom setup script should have created marker file"
    echo "  Actual output: '$MARKER'"
    FAILED=$((FAILED + 1))
fi

# Test 2: The custom command is available
TOOL_OUT=$(run_coding_booth --silence-build -- mytool 2>/dev/null | tr -d '\r\n')

if echo "$TOOL_OUT" | grep -qF "mytool version 1.0.0"; then
    print_test_result "true" "$0" "2" "Custom tool command is available"
else
    print_test_result "false" "$0" "2" "mytool command should be available"
    echo "  Actual output: '$TOOL_OUT'"
    FAILED=$((FAILED + 1))
fi

# Test 3: The profile script set the environment variable
# Wrap entire command in quotes so it's passed as single argument after --
ENV_OUT=$(run_coding_booth --silence-build -- 'bash -lc "echo \$MYTOOL_HOME"' 2>/dev/null | tr -d '\r\n')

if [[ "$ENV_OUT" == "/opt/mytool" ]]; then
    print_test_result "true" "$0" "3" "Profile script set MYTOOL_HOME"
else
    print_test_result "false" "$0" "3" "MYTOOL_HOME should be '/opt/mytool'"
    echo "  Actual output: '$ENV_OUT'"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
