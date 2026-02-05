#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile env and workdir
#
# Verifies that env and workdir commands in Boothfile correctly set
# environment variables and working directory in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile env and workdir ==="

FAILED=0

# Test 1: Environment variable is set
ENV_OUT=$(run_coding_booth --silence-build -- 'echo $MY_TEST_VAR' 2>/dev/null | tr -d '\r\n')

if [[ "$ENV_OUT" == "hello_from_boothfile" ]]; then
    print_test_result "true" "$0" "1" "MY_TEST_VAR is set correctly"
else
    print_test_result "false" "$0" "1" "MY_TEST_VAR should be 'hello_from_boothfile'"
    echo "  Actual output: '$ENV_OUT'"
    FAILED=$((FAILED + 1))
fi

# Test 2: Second environment variable is set
ENV_OUT2=$(run_coding_booth --silence-build -- 'echo $ANOTHER_VAR' 2>/dev/null | tr -d '\r\n')

if [[ "$ENV_OUT2" == "42" ]]; then
    print_test_result "true" "$0" "2" "ANOTHER_VAR is set correctly"
else
    print_test_result "false" "$0" "2" "ANOTHER_VAR should be '42'"
    echo "  Actual output: '$ENV_OUT2'"
    FAILED=$((FAILED + 1))
fi

# Test 3: Working directory exists (was created by run command)
DIR_EXISTS=$(run_coding_booth --silence-build -- 'test -d /tmp/testdir && echo "exists"' 2>/dev/null | tr -d '\r\n')

if [[ "$DIR_EXISTS" == "exists" ]]; then
    print_test_result "true" "$0" "3" "/tmp/testdir was created by run command"
else
    print_test_result "false" "$0" "3" "/tmp/testdir should exist"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
