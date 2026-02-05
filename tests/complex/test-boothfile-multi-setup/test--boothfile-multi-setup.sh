#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Multiple Setups
#
# Verifies that a Boothfile can install multiple tools (Python + Node.js)
# and pip packages in a single configuration.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Multiple Setups ==="

FAILED=0

# Test 1: Python is installed
PYTHON_OUT=$(run_coding_booth --silence-build -- python3 --version 2>/dev/null | head -1)

if echo "$PYTHON_OUT" | grep -qE "Python 3\.12"; then
    print_test_result "true" "$0" "1" "Python 3.12 is installed"
else
    print_test_result "false" "$0" "1" "Python 3.12 should be installed"
    echo "  Actual output: $PYTHON_OUT"
    FAILED=$((FAILED + 1))
fi

# Test 2: Node.js is installed
NODE_OUT=$(run_coding_booth --silence-build -- node --version 2>/dev/null | head -1)

if echo "$NODE_OUT" | grep -qE "v20\."; then
    print_test_result "true" "$0" "2" "Node.js v20 is installed"
else
    print_test_result "false" "$0" "2" "Node.js v20 should be installed"
    echo "  Actual output: $NODE_OUT"
    FAILED=$((FAILED + 1))
fi

# Test 3: requests package is installed via pip
REQUESTS_OUT=$(run_coding_booth --silence-build -- 'python3 -c "import requests; print(requests.__version__)"' 2>/dev/null | head -1)

if echo "$REQUESTS_OUT" | grep -qE "^[0-9]+\."; then
    print_test_result "true" "$0" "3" "requests package is installed via pip"
else
    print_test_result "false" "$0" "3" "requests package should be installed"
    echo "  Actual output: $REQUESTS_OUT"
    FAILED=$((FAILED + 1))
fi

# Test 4: Both tools work together (run node and python in sequence)
COMBO_OUT=$(run_coding_booth --silence-build -- 'python3 --version && node --version' 2>/dev/null)

if echo "$COMBO_OUT" | grep -qE "Python 3" && echo "$COMBO_OUT" | grep -qE "v20"; then
    print_test_result "true" "$0" "4" "Both Python and Node.js work together"
else
    print_test_result "false" "$0" "4" "Both tools should work together"
    echo "  Actual output: $COMBO_OUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
