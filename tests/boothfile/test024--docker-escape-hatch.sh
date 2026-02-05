#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: DOCKER escape hatch passthrough

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

DOCKER HEALTHCHECK CMD curl -f http://localhost/ || exit 1
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

if echo "$ACTUAL" | grep -qF "HEALTHCHECK CMD curl -f http://localhost/ || exit 1"; then
    print_test_result "true" "$0" "024" "DOCKER escape hatch passes through correctly"
else
    print_test_result "false" "$0" "024" "DOCKER escape hatch passes through correctly"
    ALL_PASSED=false
fi

# Should NOT have "DOCKER" prefix in output
if echo "$ACTUAL" | grep -qF "DOCKER HEALTHCHECK"; then
    print_test_result "false" "$0" "024" "DOCKER prefix should be stripped"
    ALL_PASSED=false
else
    print_test_result "true" "$0" "024" "DOCKER prefix is stripped"
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
