#!/bin/bash
set -euo pipefail

# Source workspace to get the PrintCmd function
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
  local expected_output="$TEST_EXPECTED_OUTPUT"
  
  test_count=$((test_count + 1))
  
  # Call PrintCmd with test args and capture output
  local actual_output
  eval "actual_output=\$(PrintCmd ${TEST_ARGS})"
  
  # Check results
  if [[ "$actual_output" == "$expected_output" ]]; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "Expected: $expected_output"
    echo "Actual:   $actual_output"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: Simple command
TEST_NAME="Simple command"
TEST_ARGS="echo hello"
TEST_EXPECTED_OUTPUT="echo hello "
run_test

# Test 2: Command with special characters (needs quoting)
TEST_NAME="Command with spaces needs quoting"
TEST_ARGS="'echo' 'hello world'"
TEST_EXPECTED_OUTPUT="echo 'hello world' "
run_test

# Test 3: Command with single quotes
TEST_NAME="Command with single quotes"
TEST_ARGS="echo \"it's\""
TEST_EXPECTED_OUTPUT="echo 'it'\''s' "
run_test

# Test 4: Multiple simple args
TEST_NAME="Multiple simple args"
TEST_ARGS="docker run -it ubuntu"
TEST_EXPECTED_OUTPUT="docker run -it ubuntu "
run_test

# Test 5: Args with paths
TEST_NAME="Args with paths"
TEST_ARGS="/usr/bin/docker /path/to/file"
TEST_EXPECTED_OUTPUT="/usr/bin/docker /path/to/file "
run_test

# Test 6: Args with special characters
TEST_NAME="Args with special characters"
TEST_ARGS="'echo' 'hello\$world'"
TEST_EXPECTED_OUTPUT="echo 'hello\$world' "
run_test

# Test 7: Empty command
TEST_NAME="Empty command"
TEST_ARGS=""
TEST_EXPECTED_OUTPUT=""
run_test

# Test 8: Command with equals sign (gets quoted)
TEST_NAME="Command with equals sign"
TEST_ARGS="--env=VALUE"
TEST_EXPECTED_OUTPUT="'--env=VALUE' "
run_test

# Test 9: Command with colons
TEST_NAME="Command with colons"
TEST_ARGS="image:tag"
TEST_EXPECTED_OUTPUT="image:tag "
run_test

# Test 10: Mixed simple and complex args
TEST_NAME="Mixed simple and complex args"
TEST_ARGS="docker run 'my image' --name=test"
TEST_EXPECTED_OUTPUT="docker run 'my image' '--name=test' "
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
