#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: run with semicolon-join heredoc (run ;<<END)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

run ;<<END
rm -f /tmp/optional
echo "done"
END
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# Should have first command and join with ;
if echo "$ACTUAL" | grep -qF "rm -f /tmp/optional"; then
    print_test_result "true" "$0" "009" "First command is present"
else
    print_test_result "false" "$0" "009" "First command is present"
    ALL_PASSED=false
fi

# Should have semicolon joiner
if echo "$ACTUAL" | grep -qE '; echo "done"'; then
    print_test_result "true" "$0" "009" "Semi-join with semicolon"
else
    print_test_result "false" "$0" "009" "Semi-join with semicolon"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
