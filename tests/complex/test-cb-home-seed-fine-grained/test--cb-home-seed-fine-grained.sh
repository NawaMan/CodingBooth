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
#
# Tests 1-6 all sit under a subtree that carries a .mount-this somewhere, so they
# exercise smart_copy's entry-by-entry walk. Tests 7-10 use a marker-free subtree,
# which it takes as a single recursive cp — the fast path that a real home seed
# (tens of thousands of files) actually lands on:
#
# Test 7: Seed marker-free dir — no-clobber (existing file preserved)
# Test 8: Seed marker-free dir — recurses into nested subdirectories
# Test 9: Seed marker-free dir — symlinks dereferenced into real files
# Test 10: Override marker-free dir — overwrites existing nested file
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

# Tests 7-10 cover the marker-free subtree, which smart_copy takes as one recursive
# cp instead of walking entry by entry. The shortcut has to be indistinguishable
# from the walk, so the same guarantees are asserted here.

# Test 7: Seed marker-free dir — no-clobber (existing file preserved)
ACTUAL=$(run_coding_booth -- cat /home/coder/.testdir-plain/data.txt 2>/dev/null | tr -d '\r\n')
EXPECTED="ORIGINAL_PLAIN_FROM_BUILD"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "7" "seed marker-free dir: no-clobber preserves existing"
else
  print_test_result "false" "$0" "7" "seed marker-free dir: no-clobber should preserve existing"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 8: Seed marker-free dir — recurses into nested subdirectories
ACTUAL=$(run_coding_booth -- cat /home/coder/.testdir-plain/nested/deep.txt 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_SEED_PLAIN_NESTED"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "8" "seed marker-free dir: copies nested files"
else
  print_test_result "false" "$0" "8" "seed marker-free dir: should copy nested files"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 9: Seed marker-free dir — symlinks are dereferenced into real files.
# A link is copied as its target's content, never as a link: the target path
# generally does not exist inside the container, so a preserved link would dangle.
ACTUAL=$(run_coding_booth -- bash -c 'test -L /home/coder/.testdir-plain/link.txt && echo LINK || cat /home/coder/.testdir-plain/link.txt' 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_SEED_PLAIN"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "9" "seed marker-free dir: dereferences symlinks"
else
  print_test_result "false" "$0" "9" "seed marker-free dir: should dereference symlinks, not preserve them"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 10: Override marker-free dir — overwrites existing nested file
ACTUAL=$(run_coding_booth -- cat /home/coder/.testdir-plain-override/nested/deep.txt 2>/dev/null | tr -d '\r\n')
EXPECTED="FROM_OVERRIDE_PLAIN_NESTED"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "10" "override marker-free dir: overwrites nested file"
else
  print_test_result "false" "$0" "10" "override marker-free dir: should overwrite nested file"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
