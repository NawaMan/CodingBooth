#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Run all complex tests
#
# Complex tests are tests that require custom Dockerfiles, setup scripts,
# and more elaborate configurations.
#
# Test discovery:
# - Looks for directories matching test-*/
# - Each directory should contain a script named test--<name>.sh
#   where <name> is the directory name without the "test-" prefix
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================"
echo "Running Complex Tests"
echo "============================================================"

FAILED=0
PASSED=0
FAILED_TESTS=()

# Loop over all test-* directories
for test_dir in test-*/; do
  # Remove trailing slash
  test_dir="${test_dir%/}"

  # Extract test name (remove "test-" prefix)
  test_name="${test_dir#test-}"

  # Expected script name
  test_script="test--${test_name}.sh"

  # Check if test script exists
  if [[ ! -x "${test_dir}/${test_script}" ]]; then
    echo ""
    echo "--- Skipping: ${test_dir} (no executable ${test_script}) ---"
    continue
  fi

  echo ""
  echo "--- Running: ${test_dir} ---"
  if (cd "${test_dir}" && "./${test_script}"); then
    echo "PASSED: ${test_dir}"
    PASSED=$((PASSED + 1))
  else
    echo "FAILED: ${test_dir}"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("${test_dir}")
  fi
done

echo ""
echo "============================================================"
TOTAL=$((PASSED + FAILED))
echo "Results: ${PASSED}/${TOTAL} passed"

if [ $FAILED -eq 0 ]; then
  echo "All complex tests passed!"
  exit 0
else
  echo ""
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  - $test"
  done
  exit 1
fi
