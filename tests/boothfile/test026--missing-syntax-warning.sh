#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: Missing syntax directive produces warning

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
run echo "no syntax line"
EOF

# Capture both stdout and stderr
OUTPUT=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>&1) || true

ALL_PASSED=true

# Should produce a warning about missing syntax
if echo "$OUTPUT" | grep -qi "syntax\|missing\|expected"; then
    print_test_result "true" "$0" "026" "Warning about missing syntax directive"
else
    print_test_result "false" "$0" "026" "Warning about missing syntax directive"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi
