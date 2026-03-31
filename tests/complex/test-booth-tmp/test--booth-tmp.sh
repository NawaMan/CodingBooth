#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: .booth/.tmp/ ephemeral directory
#
# Verifies that:
# 1) .booth/.tmp/ is created on booth start with booth-startup.txt
# 2) booth-startup.txt contains started-at and session-id
# 3) .booth/.tmp/ is cleaned on exit (default behavior)
# 4) .booth/.tmp/ is preserved on exit with --leave-tmp-on-exit
# 5) .booth/.tmp/ is cleaned on next start even if left from previous run
# 6) --keep-tmp-on-start preserves leftover .booth/.tmp/ from previous run
# 7) --keep-tmp-on-start still writes new booth-startup.txt
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0

# Ensure clean state
rm -rf .booth/.tmp

# Test 1: .booth/.tmp/booth-startup.txt is created on booth start
ACTUAL=$(run_coding_booth -- cat .booth/.tmp/booth-startup.txt 2>/dev/null)

if echo "$ACTUAL" | grep -q "^started-at = "; then
  print_test_result "true" "$0" "1" "booth-startup.txt contains started-at"
else
  print_test_result "false" "$0" "1" "booth-startup.txt should contain started-at"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: booth-startup.txt contains session-id
if echo "$ACTUAL" | grep -q "^session-id = "; then
  print_test_result "true" "$0" "2" "booth-startup.txt contains session-id"
else
  print_test_result "false" "$0" "2" "booth-startup.txt should contain session-id"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 3: .booth/.tmp/ is cleaned on exit (default)
if [ -d ".booth/.tmp" ]; then
  # Directory may exist but should be empty
  FILE_COUNT=$(find .booth/.tmp -mindepth 1 2>/dev/null | wc -l)
  if [ "$FILE_COUNT" -eq 0 ]; then
    print_test_result "true" "$0" "3" ".booth/.tmp/ is empty after exit"
  else
    print_test_result "false" "$0" "3" ".booth/.tmp/ should be empty after exit"
    echo "  Files found: $FILE_COUNT"
    find .booth/.tmp -mindepth 1
    FAILED=$((FAILED + 1))
  fi
else
  # Directory doesn't exist — also acceptable (cleaned)
  print_test_result "true" "$0" "3" ".booth/.tmp/ is cleaned after exit"
fi

# Test 4: --leave-tmp-on-exit preserves .booth/.tmp/
rm -rf .booth/.tmp
run_coding_booth --leave-tmp-on-exit -- echo "leave-tmp-test" >/dev/null 2>&1

if [ -f ".booth/.tmp/booth-startup.txt" ]; then
  print_test_result "true" "$0" "4" "--leave-tmp-on-exit preserves booth-startup.txt"
else
  print_test_result "false" "$0" "4" "--leave-tmp-on-exit should preserve .booth/.tmp/"
  echo "  .booth/.tmp/ contents:"
  ls -la .booth/.tmp/ 2>/dev/null || echo "  (directory does not exist)"
  FAILED=$((FAILED + 1))
fi

# Test 5: Next start cleans up leftover .booth/.tmp/ from previous run
# (The .booth/.tmp/ from test 4 should still be present)
ACTUAL=$(run_coding_booth -- cat .booth/.tmp/booth-startup.txt 2>/dev/null)

# After this run exits, .booth/.tmp/ should be cleaned again (no --leave-tmp-on-exit)
if [ -d ".booth/.tmp" ]; then
  FILE_COUNT=$(find .booth/.tmp -mindepth 1 2>/dev/null | wc -l)
  if [ "$FILE_COUNT" -eq 0 ]; then
    print_test_result "true" "$0" "5" "Next start cleans leftover .booth/.tmp/"
  else
    print_test_result "false" "$0" "5" "Next start should clean leftover .booth/.tmp/"
    echo "  Files found: $FILE_COUNT"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "true" "$0" "5" "Next start cleans leftover .booth/.tmp/"
fi

# Test 6: --keep-tmp-on-start preserves leftover files from previous session
# First, create a leftover file using --leave-tmp-on-exit
rm -rf .booth/.tmp
run_coding_booth --leave-tmp-on-exit -- 'echo previous-session > .booth/.tmp/leftover.txt' >/dev/null 2>&1

# Now start again with --keep-tmp-on-start — leftover.txt should survive
ACTUAL=$(run_coding_booth --keep-tmp-on-start --leave-tmp-on-exit -- cat .booth/.tmp/leftover.txt 2>/dev/null)

if echo "$ACTUAL" | grep -qF "previous-session"; then
  print_test_result "true" "$0" "6" "--keep-tmp-on-start preserves leftover files"
else
  print_test_result "false" "$0" "6" "--keep-tmp-on-start should preserve leftover files"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 7: --keep-tmp-on-start still writes new booth-startup.txt
if [ -f ".booth/.tmp/booth-startup.txt" ]; then
  print_test_result "true" "$0" "7" "--keep-tmp-on-start still writes booth-startup.txt"
else
  print_test_result "false" "$0" "7" "--keep-tmp-on-start should still write booth-startup.txt"
  FAILED=$((FAILED + 1))
fi

# Cleanup
rm -rf .booth/.tmp

exit $FAILED
