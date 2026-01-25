#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: .booth/startup.sh
#
# This test verifies that .booth/startup.sh runs correctly at container start.
#
# Test 1: Verify the startup script ran (created a marker file)
# Test 2: Verify the script runs as the coder user
# Test 3: Verify HOME environment variable is set correctly
# Test 4: Verify the working directory is the code directory
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: .booth/startup.sh ==="

FAILED=0

# Test 1: Verify startup script ran
ACTUAL=$(../../../coding-booth -- cat /home/coder/.startup-test 2>/dev/null | tr -d '\r\n')
EXPECTED="STARTUP_SCRIPT_RAN"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" ".booth/startup.sh ran successfully"
else
  print_test_result "false" "$0" "1" ".booth/startup.sh should run at container start"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: Verify script runs as coder user
ACTUAL=$(../../../coding-booth -- cat /home/coder/.startup-user 2>/dev/null | tr -d '\r\n')
EXPECTED="coder"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "2" ".booth/startup.sh runs as coder user"
else
  print_test_result "false" "$0" "2" ".booth/startup.sh should run as coder user"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 3: Verify HOME is set correctly
ACTUAL=$(../../../coding-booth -- cat /home/coder/.startup-home 2>/dev/null | tr -d '\r\n')
EXPECTED="/home/coder"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "3" "HOME environment variable is correct"
else
  print_test_result "false" "$0" "3" "HOME should be /home/coder"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 4: Verify working directory is code directory
ACTUAL=$(../../../coding-booth -- cat /home/coder/.startup-pwd 2>/dev/null | tr -d '\r\n')
EXPECTED="/home/coder/code"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "4" "Working directory is /home/coder/code"
else
  print_test_result "false" "$0" "4" "Working directory should be /home/coder/code"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
