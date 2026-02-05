#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Commands emitted in exact source order

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

env FIRST=1
setup python 3.12
env SECOND=2
install pip django
env THIRD=3
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# Extract line numbers for each command
LINE_FIRST=$(echo "$ACTUAL" | grep -n "ENV FIRST=1" | cut -d: -f1)
LINE_PYTHON=$(echo "$ACTUAL" | grep -n "RUN python--setup.sh 3.12" | cut -d: -f1)
LINE_SECOND=$(echo "$ACTUAL" | grep -n "ENV SECOND=2" | cut -d: -f1)
LINE_PIP=$(echo "$ACTUAL" | grep -n "RUN pip--install.sh django" | cut -d: -f1)
LINE_THIRD=$(echo "$ACTUAL" | grep -n "ENV THIRD=3" | cut -d: -f1)

# Verify order
if [[ -n "$LINE_FIRST" && -n "$LINE_PYTHON" && "$LINE_FIRST" -lt "$LINE_PYTHON" ]]; then
    print_test_result "true" "$0" "025" "FIRST comes before python setup"
else
    print_test_result "false" "$0" "025" "FIRST comes before python setup"
    ALL_PASSED=false
fi

if [[ -n "$LINE_PYTHON" && -n "$LINE_SECOND" && "$LINE_PYTHON" -lt "$LINE_SECOND" ]]; then
    print_test_result "true" "$0" "025" "python setup comes before SECOND"
else
    print_test_result "false" "$0" "025" "python setup comes before SECOND"
    ALL_PASSED=false
fi

if [[ -n "$LINE_SECOND" && -n "$LINE_PIP" && "$LINE_SECOND" -lt "$LINE_PIP" ]]; then
    print_test_result "true" "$0" "025" "SECOND comes before pip install"
else
    print_test_result "false" "$0" "025" "SECOND comes before pip install"
    ALL_PASSED=false
fi

if [[ -n "$LINE_PIP" && -n "$LINE_THIRD" && "$LINE_PIP" -lt "$LINE_THIRD" ]]; then
    print_test_result "true" "$0" "025" "pip install comes before THIRD"
else
    print_test_result "false" "$0" "025" "pip install comes before THIRD"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
