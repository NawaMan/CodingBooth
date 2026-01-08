#!/bin/bash
set -euo pipefail

# Source workspace to get the PrepareTtyArgs function
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  
  test_count=$((test_count + 1))
  
  # Reset TTY_ARGS
  TTY_ARGS=()
  
  # Call PrepareTtyArgs
  PrepareTtyArgs
  
  # Check results
  local all_match=true
  local mismatches=""
  local args_string="${TTY_ARGS[*]}"
  
  # We expect either "-i" or "-it" depending on terminal state
  if [[ "$args_string" == "-i" ]] || [[ "$args_string" == "-it" ]]; then
    # Valid result
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name (got: $args_string)"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "  TTY_ARGS: expected '-i' or '-it', actual='$args_string'"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: Check TTY args are set
TEST_NAME="TTY args are set correctly"
run_test

# Summary
echo ""
echo "==============================================================================="
echo "Test Summary"
echo "==============================================================================="
echo "Total tests: $test_count"
echo "Passed:      $pass_count"
echo "Failed:      $fail_count"
echo "==============================================================================="
echo ""
echo "NOTE: This function checks if stdin/stdout are terminals using [ -t 0 ] and"
echo "      [ -t 1 ]. The result will be '-i' (non-interactive) or '-it' (interactive)"
echo "      depending on the test environment."
echo "==============================================================================="

if [ $fail_count -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed!"
  exit 1
fi
