#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --persist-home dryrun output
#
# Verifies that --persist-home produces the expected Docker volume mount
# and environment variable in dry-run output.
#
# Test 1: Output contains volume create command
# Test 2: Output contains -v cb-home-<name>:/home/coder mount
# Test 3: Output contains BOOTH_HOME_PERSISTED=true env var
# Test 4: Output contains cb.persist-home=true label
# Test 5: Volume mount appears BEFORE code mount (ordering check)
# Test 6: Without --persist-home, none of the above appear
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

FAILED=0

ACTUAL=$(run_coding_booth --dryrun --persist-home --variant base -- sleep 1 2>&1)

# Test 1: volume create command
if echo "$ACTUAL" | grep -q "volume"; then
  if echo "$ACTUAL" | grep -q "create"; then
    print_test_result "true" "$0" "1" "Output contains docker volume create command"
  else
    print_test_result "false" "$0" "1" "Output should contain docker volume create command"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "Output should contain docker volume command"
  FAILED=$((FAILED + 1))
fi

# Test 2: volume mount
if echo "$ACTUAL" | grep -q "cb-home-dryrun:/home/coder"; then
  print_test_result "true" "$0" "2" "Output contains -v cb-home-dryrun:/home/coder mount"
else
  print_test_result "false" "$0" "2" "Output should contain -v cb-home-dryrun:/home/coder"
  echo "  Actual output:"
  echo "$ACTUAL" | head -20
  FAILED=$((FAILED + 1))
fi

# Test 3: BOOTH_HOME_PERSISTED env var
if echo "$ACTUAL" | grep -q "BOOTH_HOME_PERSISTED=true"; then
  print_test_result "true" "$0" "3" "Output contains BOOTH_HOME_PERSISTED=true env var"
else
  print_test_result "false" "$0" "3" "Output should contain BOOTH_HOME_PERSISTED=true"
  FAILED=$((FAILED + 1))
fi

# Test 4: cb.persist-home label
if echo "$ACTUAL" | grep -q "cb.persist-home=true"; then
  print_test_result "true" "$0" "4" "Output contains cb.persist-home=true label"
else
  print_test_result "false" "$0" "4" "Output should contain cb.persist-home=true label"
  FAILED=$((FAILED + 1))
fi

# Test 5: Volume mount ordering — cb-home-dryrun:/home/coder must appear BEFORE :/home/coder/code
VOL_LINE=$(echo "$ACTUAL" | grep -n "cb-home-dryrun:/home/coder" | head -1 | cut -d: -f1)
CODE_LINE=$(echo "$ACTUAL" | grep -n ":/home/coder/code" | head -1 | cut -d: -f1)
if [[ -n "$VOL_LINE" ]] && [[ -n "$CODE_LINE" ]] && [[ "$VOL_LINE" -lt "$CODE_LINE" ]]; then
  print_test_result "true" "$0" "5" "Home volume mount appears before code mount"
else
  print_test_result "false" "$0" "5" "Home volume mount should appear before code mount (vol=$VOL_LINE, code=$CODE_LINE)"
  FAILED=$((FAILED + 1))
fi

# Test 6: Control — without --persist-home, none of the above should appear
CONTROL=$(run_coding_booth --dryrun --variant base -- sleep 1 2>&1)

CONTROL_PASS=true
if echo "$CONTROL" | grep -q "cb-home-dryrun:/home/coder"; then
  CONTROL_PASS=false
fi
if echo "$CONTROL" | grep -q "BOOTH_HOME_PERSISTED"; then
  CONTROL_PASS=false
fi
if echo "$CONTROL" | grep -q "cb.persist-home"; then
  CONTROL_PASS=false
fi

if [[ "$CONTROL_PASS" == "true" ]]; then
  print_test_result "true" "$0" "6" "Without --persist-home, no volume/env/label appears (control)"
else
  print_test_result "false" "$0" "6" "Without --persist-home, persist-home output should not appear"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
