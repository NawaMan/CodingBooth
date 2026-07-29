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

# Record every booth invocation's command, exit code, and stderr for this suite.
# Complex tests discard booth's stderr (`2>/dev/null`), so when a run intermittently
# returns nothing the suite reports `FAILED:` with no output and nothing to go on.
# This is the trace that makes the next such failure explain itself.
# Opt out with CB_DIAG_LOG=/dev/null; point it elsewhere to relocate the log.
if [[ -z "${CB_DIAG_LOG:-}" ]]; then
  export CB_DIAG_LOG="${SCRIPT_DIR}/../logs/complex-booth-calls.log"
  mkdir -p "$(dirname "$CB_DIAG_LOG")"
  : >"$CB_DIAG_LOG"
  echo "Booth call trace: ${CB_DIAG_LOG}"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: Docker is not installed or not in PATH"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "SKIP: Docker daemon is not accessible (permission or not running)"
  exit 0
fi

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
