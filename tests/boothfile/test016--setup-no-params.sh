#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: setup command without parameters

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

setup python
setup nodejs
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

if echo "$ACTUAL" | grep -qF "RUN python--setup.sh"; then
    print_test_result "true" "$0" "016" "setup python compiles to RUN python--setup.sh"
else
    print_test_result "false" "$0" "016" "setup python compiles to RUN python--setup.sh"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "RUN nodejs--setup.sh"; then
    print_test_result "true" "$0" "016" "setup nodejs compiles to RUN nodejs--setup.sh"
else
    print_test_result "false" "$0" "016" "setup nodejs compiles to RUN nodejs--setup.sh"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
