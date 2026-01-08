#!/bin/bash
set -euo pipefail

# Source workspace to get the PortBanner function
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
  local test_port="$TEST_PORT"
  local expected_output="$TEST_EXPECTED_OUTPUT"
  
  test_count=$((test_count + 1))
  
  # Call PortBanner and capture output
  local actual_output=$(PortBanner "$test_port" 2>&1)
  
  # Check if expected strings are in output
  local all_match=true
  local mismatches=""
  
  # Check for port number in output
  if [[ "$actual_output" != *"$test_port"* ]]; then
    all_match=false
    mismatches+="  Port number '$test_port' not found in output"$'\n'
  fi
  
  # Check for expected strings
  if [[ "$actual_output" != *"WORKSPACE PORT SELECTED"* ]]; then
    all_match=false
    mismatches+="  Missing 'WORKSPACE PORT SELECTED' header"$'\n'
  fi
  
  if [[ "$actual_output" != *"Using host port:"* ]]; then
    all_match=false
    mismatches+="  Missing 'Using host port:' text"$'\n'
  fi
  
  if [[ "$actual_output" != *"http://localhost:${test_port}"* ]]; then
    all_match=false
    mismatches+="  Missing URL with port $test_port"$'\n'
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

# Test 1: Standard port
TEST_NAME="Standard port 8080"
TEST_PORT="8080"
TEST_EXPECTED_OUTPUT="8080"
run_test

# Test 2: Port 10000
TEST_NAME="Default port 10000"
TEST_PORT="10000"
TEST_EXPECTED_OUTPUT="10000"
run_test

# Test 3: High port number
TEST_NAME="High port 65535"
TEST_PORT="65535"
TEST_EXPECTED_OUTPUT="65535"
run_test

# Test 4: Low port number
TEST_NAME="Low port 80"
TEST_PORT="80"
TEST_EXPECTED_OUTPUT="80"
run_test

# Test 5: Port 3000
TEST_NAME="Port 3000"
TEST_PORT="3000"
TEST_EXPECTED_OUTPUT="3000"
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
