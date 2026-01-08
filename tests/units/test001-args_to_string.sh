#!/bin/bash
set -euo pipefail

# Source workspace to get the args_to_string function
# Set SKIP_MAIN to prevent the main script from executing
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
  local expected="$TEST_EXPECTED"
  local actual
  
  test_count=$((test_count + 1))
  
  # Call args_to_string with remaining arguments
  actual=$(args_to_string "$@")
  
  if diff -u <(echo "$expected") <(echo "$actual") >/dev/null 2>&1; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "Expected: "
    echo "$expected"
    echo "-------------------------------------------------------------------------------"
    echo "Actual: "
    echo "$actual"
    echo "-------------------------------------------------------------------------------"
    diff -u <(echo "$expected") <(echo "$actual") || true
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: No arguments
TEST_NAME="No arguments" \
TEST_EXPECTED=""         \
run_test

# Test 2: Single argument
TEST_NAME="Single argument" \
TEST_EXPECTED=' "hello"'    \
run_test "hello"

# Test 3: Multiple arguments
TEST_NAME="Multiple arguments"       \
TEST_EXPECTED=' "one" "two" "three"' \
run_test "one" "two" "three"

# Test 4: Arguments with spaces
TEST_NAME="Arguments with spaces"        \
TEST_EXPECTED=' "hello world" "foo bar"' \
run_test "hello world" "foo bar"

# Test 5: Arguments with special characters
TEST_NAME="Special characters"                \
TEST_EXPECTED=' "hello!" "world?" "test@123"' \
run_test "hello!" "world?" "test@123"

# Test 6: Arguments with quotes
TEST_NAME="Arguments with quotes"              \
TEST_EXPECTED=' "say "hello"" "it'"'"'s fine"' \
run_test 'say "hello"' "it's fine"

# Test 7: Empty string argument
TEST_NAME="Empty string argument" \
TEST_EXPECTED=' ""'               \
run_test ""

# Test 8: Mixed empty and non-empty
TEST_NAME="Mixed empty and non-empty" \
TEST_EXPECTED=' "" "hello" ""'       \
run_test "" "hello" ""

# Test 9: Arguments with newlines (escaped)
TEST_NAME="Arguments with newlines"       \
TEST_EXPECTED=$' "line1\nline2" "single"' \
run_test $'line1\nline2' "single"

# Test 10: Arguments with tabs
TEST_NAME="Arguments with tabs"           \
TEST_EXPECTED=$' "tab\there" "normal"'    \
run_test $'tab\there' "normal"

# Test 11: Long argument list
TEST_NAME="Long argument list"                           \
TEST_EXPECTED=' "a" "b" "c" "d" "e" "f" "g" "h" "i" "j"' \
run_test "a" "b" "c" "d" "e" "f" "g" "h" "i" "j"

# Test 12: Arguments with backslashes
TEST_NAME="Arguments with backslashes"       \
TEST_EXPECTED=' "path\to\file" "back\slash"' \
run_test 'path\to\file' 'back\slash'

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
