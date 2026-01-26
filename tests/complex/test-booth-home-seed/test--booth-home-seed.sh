#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: .booth/home-seed
#
# Test 1 (no-clobber): Verifies that .booth/home-seed does NOT overwrite existing files
# Test 2 (normal copy): Verifies that .booth/home-seed DOES copy files when they don't exist
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: .booth/home-seed ==="

FAILED=0

# Test 1: No-clobber - existing file should NOT be overwritten
ACTUAL=$(run_coding_booth -- cat /home/coder/.testfile 2>/dev/null | tr -d '\r\n')
EXPECTED="ORIGINAL_FROM_BUILD"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" ".booth/home-seed did NOT overwrite existing file (no-clobber works)"
else
  print_test_result "false" "$0" "1" ".booth/home-seed should NOT overwrite existing file"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: Normal copy - non-existing file SHOULD be copied
ACTUAL=$(run_coding_booth -- cat /home/coder/.testfile-normal 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_BOOTH_HOME_SEED_NORMAL"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "2" ".booth/home-seed DID copy new file (normal copy works)"
else
  print_test_result "false" "$0" "2" ".booth/home-seed should copy new file when it doesn't exist"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
