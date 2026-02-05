#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: --strict mode treats warnings as errors

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
# Missing syntax directive should be a warning normally
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
run echo "no syntax line"
EOF

# Without --strict, should succeed (warning only)
set +e
OUTPUT_NORMAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>&1)
EXIT_NORMAL=$?
set -e

# With --strict, should fail
set +e
OUTPUT_STRICT=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" --strict 2>&1)
EXIT_STRICT=$?
set -e

ALL_PASSED=true

# In strict mode, should fail
if [[ "$EXIT_STRICT" -ne 0 ]]; then
    print_test_result "true" "$0" "030" "--strict causes non-zero exit on warning"
else
    # Some implementations might not have strict mode yet
    print_test_result "false" "$0" "030" "--strict causes non-zero exit on warning (may not be implemented)"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Normal output (exit $EXIT_NORMAL):"
    echo "$OUTPUT_NORMAL"
    echo ""
    echo "Strict output (exit $EXIT_STRICT):"
    echo "$OUTPUT_STRICT"
    exit 1
fi
