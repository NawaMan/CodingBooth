#!/bin/bash
set -euo pipefail

# Source workspace to get the require_arg function
# Set SKIP_MAIN to prevent the main script from executing
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function for successful cases
run_test() {
  local test_name="$TEST_NAME"
  local opt="$TEST_OPT"
  local val="$TEST_VAL"
  
  test_count=$((test_count + 1))
  
  # Call require_arg - should succeed (exit 0, no output)
  if require_arg "$opt" "$val" 2>/dev/null; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "  Expected: success (exit 0)"
    echo "  Actual:   failed (exit $?)"
    fail_count=$((fail_count + 1))
  fi
}

# Test helper function for error cases
run_error_test() {
  local test_name="$TEST_NAME"
  local opt="$TEST_OPT"
  local val="${TEST_VAL-__MISSING__}"  # Special marker for missing argument
  local expected_error="$TEST_EXPECTED_ERROR"
  local actual_error
  local exit_code
  
  test_count=$((test_count + 1))
  
  # Call require_arg in a subshell and capture stderr
  if [[ "$val" == "__MISSING__" ]]; then
    # Test with missing second argument
    actual_error=$( (require_arg "$opt") 2>&1 || true)
    exit_code=$?
  else
    actual_error=$( (require_arg "$opt" "$val") 2>&1 || true)
    exit_code=$?
  fi
  
  # Check if error message contains expected text
  script_relative_path() {
    local script_abs="${1:-$0}"                # absolute path of the script
    local root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

    # Make sure both paths are absolute (realpath handles symlinks too)
    script_abs=$(realpath "$script_abs")
    root=$(realpath "$root")

    # Strip "<root>/tests/" from the front
    echo "${script_abs#${root}/tests/}"
  }

  local script_title=$(script_relative_path "$0")

  if [[ "$actual_error" == *"$expected_error"* ]]; then
    echo "✅ ${script_title}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${script_title}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "Expected error containing: "
    echo "$expected_error"
    echo "-------------------------------------------------------------------------------"
    echo "Actual error: "
    echo "$actual_error"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: Valid simple value
TEST_NAME="Valid simple value" \
TEST_OPT="--name"              \
TEST_VAL="myproject"           \
run_test

# Test 2: Valid value with spaces
TEST_NAME="Valid value with spaces" \
TEST_OPT="--name"                   \
TEST_VAL="my project"               \
run_test

# Test 3: Valid value with special characters
TEST_NAME="Valid value with special chars" \
TEST_OPT="--port"                          \
TEST_VAL="8080"                            \
run_test

# Test 4: Valid value with path
TEST_NAME="Valid value with path" \
TEST_OPT="--volume"               \
TEST_VAL="/home/user/data"        \
run_test

# Test 5: Valid value with equals sign
TEST_NAME="Valid value with equals" \
TEST_OPT="--env"                    \
TEST_VAL="KEY=value"                \
run_test

# Test 6: Valid value with single dash
TEST_NAME="Valid value with single dash" \
TEST_OPT="--name"                        \
TEST_VAL="-value"                        \
run_test

# Test 7: Valid numeric value
TEST_NAME="Valid numeric value" \
TEST_OPT="--port"               \
TEST_VAL="3000"                 \
run_test

# Test 8: Valid value with underscores
TEST_NAME="Valid value with underscores" \
TEST_OPT="--name"                        \
TEST_VAL="my_project_name"               \
run_test

# Test 9: Valid value with dots
TEST_NAME="Valid value with dots" \
TEST_OPT="--file"                 \
TEST_VAL="config.yaml"            \
run_test

# Test 10: Valid value that is a single character
TEST_NAME="Valid single character value" \
TEST_OPT="--flag"                        \
TEST_VAL="y"                             \
run_test

# Test 11: Empty value → error
TEST_NAME="Empty value"                \
TEST_OPT="--name"                      \
TEST_VAL=""                            \
TEST_EXPECTED_ERROR="requires a value" \
run_error_test

# Test 12: Missing value (no second argument) → error
TEST_NAME="Missing value"              \
TEST_OPT="--name"                      \
TEST_VAL="__MISSING__"                 \
TEST_EXPECTED_ERROR="requires a value" \
run_error_test

# Test 13: Value starting with -- → error
TEST_NAME="Value starts with --"       \
TEST_OPT="--name"                      \
TEST_VAL="--another-option"            \
TEST_EXPECTED_ERROR="requires a value" \
run_error_test

# Test 14: Value is exactly -- → error
TEST_NAME="Value is exactly --"        \
TEST_OPT="--name"                      \
TEST_VAL="--"                          \
TEST_EXPECTED_ERROR="requires a value" \
run_error_test

# Test 15: Value starting with --- → error
TEST_NAME="Value starts with ---"      \
TEST_OPT="--name"                      \
TEST_VAL="---value"                    \
TEST_EXPECTED_ERROR="requires a value" \
run_error_test

# Test 16: Value starting with --= → error
TEST_NAME="Value starts with --="      \
TEST_OPT="--name"                      \
TEST_VAL="--=value"                    \
TEST_EXPECTED_ERROR="requires a value" \
run_error_test

# Test 17: Short option with valid value
TEST_NAME="Short option with valid value" \
TEST_OPT="-n"                             \
TEST_VAL="myproject"                      \
run_test

# Test 18: Short option with empty value → error
TEST_NAME="Short option with empty value" \
TEST_OPT="-n"                             \
TEST_VAL=""                               \
TEST_EXPECTED_ERROR="requires a value"    \
run_error_test

# Test 19: Short option with -- value → error
TEST_NAME="Short option with -- value" \
TEST_OPT="-n"                          \
TEST_VAL="--value"                     \
TEST_EXPECTED_ERROR="requires a value" \
run_error_test

# Test 20: Option without dashes, valid value
TEST_NAME="Option without dashes" \
TEST_OPT="name"                   \
TEST_VAL="myproject"              \
run_test

# Test 21: Complex option name
TEST_NAME="Complex option name" \
TEST_OPT="--my-complex-option"  \
TEST_VAL="value"                \
run_test

# Test 22: Value with leading whitespace (still valid)
TEST_NAME="Value with leading whitespace" \
TEST_OPT="--name"                         \
TEST_VAL="  value"                        \
run_test

# Test 23: Value with trailing whitespace (still valid)
TEST_NAME="Value with trailing whitespace" \
TEST_OPT="--name"                          \
TEST_VAL="value  "                         \
run_test

# Test 24: Value with newline character (still valid)
TEST_NAME="Value with newline" \
TEST_OPT="--text"               \
TEST_VAL=$'line1\nline2'        \
run_test

# Test 25: Value with tab character (still valid)
TEST_NAME="Value with tab"       \
TEST_OPT="--text"                \
TEST_VAL=$'value\twith\ttab'     \
run_test

# Test 26: Value that looks like a file path starting with --
TEST_NAME="Value like path starting with --" \
TEST_OPT="--file"                            \
TEST_VAL="--/path/to/file"                   \
TEST_EXPECTED_ERROR="requires a value"       \
run_error_test

# Test 27: Whitespace-only value → should succeed (not empty string)
TEST_NAME="Whitespace-only value" \
TEST_OPT="--name"                 \
TEST_VAL="   "                    \
run_test

# Test 28: Value with special shell characters
TEST_NAME="Value with shell special chars" \
TEST_OPT="--cmd"                           \
TEST_VAL="echo \$HOME"                     \
run_test

# Test 29: Value with quotes
TEST_NAME="Value with quotes" \
TEST_OPT="--text"             \
TEST_VAL="\"                  \
run_testquoted value\""

# Test 30: Value with backslashes
TEST_NAME="Value with backslashes" \
TEST_OPT="--path"                  \
TEST_VAL="C:\\Users\\Name"         \
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
