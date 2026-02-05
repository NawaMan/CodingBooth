#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: run with verbatim heredoc (run <<END)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

run <<END
set -e
apt-get update
apt-get install -y curl
END
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

# Should produce Docker heredoc
if echo "$ACTUAL" | grep -qF "RUN <<END"; then
    print_test_result "true" "$0" "007" "Verbatim heredoc produces RUN <<END"
else
    print_test_result "false" "$0" "007" "Verbatim heredoc produces RUN <<END"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "set -e"; then
    print_test_result "true" "$0" "007" "Heredoc content is preserved"
else
    print_test_result "false" "$0" "007" "Heredoc content is preserved"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qE "^END$"; then
    print_test_result "true" "$0" "007" "Heredoc delimiter is present"
else
    print_test_result "false" "$0" "007" "Heredoc delimiter is present"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
