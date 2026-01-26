#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: .booth/home
#
# Test 1 (override): Verifies that .booth/home DOES overwrite existing files
# Test 2 (normal copy): Verifies that .booth/home DOES copy files when they don't exist
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: .booth/home ==="

FAILED=0

# Test 1: Override - existing file SHOULD be overwritten
ACTUAL=$(run_coding_booth -- cat /home/coder/.testfile 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_BOOTH_HOME"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" ".booth/home DID overwrite existing file (override works)"
else
  print_test_result "false" "$0" "1" ".booth/home should overwrite existing file"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: Normal copy - non-existing file SHOULD be copied
ACTUAL=$(run_coding_booth -- cat /home/coder/.testfile-normal 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_BOOTH_HOME_NORMAL"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "2" ".booth/home DID copy new file (normal copy works)"
else
  print_test_result "false" "$0" "2" ".booth/home should copy new file when it doesn't exist"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
