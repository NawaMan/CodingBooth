#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: cb-home-seed and cb-home fine-grained copy with .mount-this
#
# Test 1: Seed individual file — no-clobber (existing file preserved)
# Test 2: Seed directory with .mount-this — no-clobber (existing file preserved)
# Test 3: Override individual file — overwrites existing file
# Test 4: Override directory with .mount-this — overwrites existing file
# Test 5: Seed individual file — copies when file doesn't exist yet
# Test 6: Seed .mount-this dir — copies extra file that didn't exist at build
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: cb-home-seed/cb-home fine-grained copy ==="

FAILED=0

# Test 1: Seed individual file — no-clobber (existing file preserved)
ACTUAL=$(run_coding_booth -- cat /home/coder/.testfile-individual 2>/dev/null | tr -d '\r\n')
EXPECTED="ORIGINAL_FROM_BUILD"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" "seed individual file: no-clobber preserves existing"
else
  print_test_result "false" "$0" "1" "seed individual file: no-clobber should preserve existing"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: Seed directory with .mount-this — no-clobber (existing file preserved)
ACTUAL=$(run_coding_booth -- cat /home/coder/.testdir/data.txt 2>/dev/null | tr -d '\r\n')
EXPECTED="ORIGINAL_DIR_FROM_BUILD"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "2" "seed .mount-this dir: no-clobber preserves existing"
else
  print_test_result "false" "$0" "2" "seed .mount-this dir: no-clobber should preserve existing"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 3: Override individual file — overwrites existing
ACTUAL=$(run_coding_booth -- cat /home/coder/.testfile-override 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_OVERRIDE_INDIVIDUAL"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "3" "override individual file: overwrites existing"
else
  print_test_result "false" "$0" "3" "override individual file: should overwrite existing"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 4: Override directory with .mount-this — overwrites existing
ACTUAL=$(run_coding_booth -- cat /home/coder/.testdir-override/data.txt 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_OVERRIDE_DIR"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "4" "override .mount-this dir: overwrites existing"
else
  print_test_result "false" "$0" "4" "override .mount-this dir: should overwrite existing"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 5: Seed individual file — copies when file doesn't exist yet
ACTUAL=$(run_coding_booth -- cat /home/coder/.testfile-new 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_SEED_NEW"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "5" "seed individual file: copies new file"
else
  print_test_result "false" "$0" "5" "seed individual file: should copy when file doesn't exist"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 6: Seed .mount-this dir — copies extra file that didn't exist at build
ACTUAL=$(run_coding_booth -- cat /home/coder/.testdir/extra.txt 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_SEED_DIR_EXTRA"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "6" "seed .mount-this dir: copies extra files"
else
  print_test_result "false" "$0" "6" "seed .mount-this dir: should copy extra files from seed"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
