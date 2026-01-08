#!/bin/bash
set -euo pipefail

# Source workspace to get the PrepareKeepAliveArgs function
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
  
  # Reset KEEPALIVE_ARGS
  KEEPALIVE_ARGS=()
  
  # Set KEEPALIVE variable
  KEEPALIVE="${TEST_KEEPALIVE}"
  
  # Call PrepareKeepAliveArgs
  PrepareKeepAliveArgs
  
  # Check results
  local all_match=true
  local mismatches=""
  local args_string="${KEEPALIVE_ARGS[*]}"
  local expected_string="${TEST_EXPECTED_ARGS[*]}"
  
  if [[ "$args_string" != "$expected_string" ]]; then
    all_match=false
    mismatches+="  KEEPALIVE_ARGS: expected='$expected_string', actual='$args_string'"$'\n'
  fi
  
  if $all_match; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "$mismatches"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: KEEPALIVE=false (should add --rm)
TEST_NAME="KEEPALIVE=false adds --rm"
TEST_KEEPALIVE="false"
TEST_EXPECTED_ARGS=("--rm")
run_test

# Test 2: KEEPALIVE=true (empty array)
TEST_NAME="KEEPALIVE=true removes --rm"
TEST_KEEPALIVE="true"
TEST_EXPECTED_ARGS=()
run_test

# Test 3: KEEPALIVE not set (defaults to false behavior)
TEST_NAME="KEEPALIVE unset defaults to --rm"
TEST_KEEPALIVE=""
TEST_EXPECTED_ARGS=("--rm")
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

if [ $fail_count -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed!"
  exit 1
fi
