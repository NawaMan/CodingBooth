#!/bin/bash
set -euo pipefail

# Source workspace to get the ApplyEnvFile function
# Set SKIP_MAIN to prevent the main script from executing
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

# Create a temporary directory for test files
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function for successful cases
run_test() {
  local test_name="$TEST_NAME"
  local expected_args="$TEST_EXPECTED_ARGS"
  local expected_verbose="$TEST_EXPECTED_VERBOSE"
  
  test_count=$((test_count + 1))
  
  # Reset COMMON_ARGS (unless test wants to preserve it)
  if [[ "${TEST_PRESERVE_COMMON_ARGS:-false}" != "true" ]]; then
    COMMON_ARGS=()
  fi
  
  # Capture verbose output to file (not command substitution to avoid subshell)
  local verbose_file=$(mktemp)
  ApplyEnvFile >"$verbose_file" 2>&1 || true
  local actual_verbose=$(cat "$verbose_file")
  rm -f "$verbose_file"
  
  # Convert COMMON_ARGS array to string for comparison
  local actual_args="${COMMON_ARGS[*]}"

  if diff -u <(echo "$expected_args") <(echo "$actual_args") >/dev/null 2>&1 && \
     diff -u <(echo "$expected_verbose") <(echo "$actual_verbose") >/dev/null 2>&1; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "Expected args: "
    echo "$expected_args"
    echo "-------------------------------------------------------------------------------"
    echo "Actual args: "
    echo "$actual_args"
    echo "-------------------------------------------------------------------------------"
    echo "Expected verbose: "
    echo "$expected_verbose"
    echo "-------------------------------------------------------------------------------"
    echo "Actual verbose: "
    echo "$actual_verbose"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test helper function for error cases
run_error_test() {
  local test_name="$TEST_NAME"
  local expected_error="$TEST_EXPECTED_ERROR"
  local actual_error
  
  test_count=$((test_count + 1))
  
  # Reset COMMON_ARGS
  COMMON_ARGS=()
  
  # Call ApplyEnvFile in a subshell and capture stderr
  actual_error=$( (ApplyEnvFile) 2>&1 || true)
  
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

# Setup test files
ENV_FILE_1="$TEST_DIR/.env"
ENV_FILE_2="$TEST_DIR/custom.env"
WORKSPACE_DIR="$TEST_DIR/workspace"
mkdir -p "$WORKSPACE_DIR"

echo "KEY1=value1" > "$ENV_FILE_1"
echo "KEY2=value2" > "$ENV_FILE_2"
echo "KEY3=value3" > "$WORKSPACE_DIR/.env"

# Test 1: No CONTAINER_ENV_FILE set, no .env in current dir → no args added
unset CONTAINER_ENV_FILE
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="No env file set, no default .env" \
TEST_EXPECTED_ARGS=""                        \
TEST_EXPECTED_VERBOSE=""                     \
run_test

# Test 2: No CONTAINER_ENV_FILE set, .env exists in WORKSPACE_PATH → use it
unset CONTAINER_ENV_FILE
WORKSPACE_PATH="$WORKSPACE_DIR"
VERBOSE=false
TEST_NAME="Default to workspace .env"               \
TEST_EXPECTED_ARGS="--env-file $WORKSPACE_DIR/.env" \
TEST_EXPECTED_VERBOSE=""                            \
run_test

# Test 3: No CONTAINER_ENV_FILE set, .env exists in current dir → use it
unset CONTAINER_ENV_FILE
unset WORKSPACE_PATH
cd "$TEST_DIR"
VERBOSE=false
TEST_NAME="Default to current dir .env" \
TEST_EXPECTED_ARGS="--env-file ./.env"   \
TEST_EXPECTED_VERBOSE=""                 \
run_test
cd - >/dev/null

# Test 4: CONTAINER_ENV_FILE explicitly set → use it
CONTAINER_ENV_FILE="$ENV_FILE_2"
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="Explicitly set env file"         \
TEST_EXPECTED_ARGS="--env-file $ENV_FILE_2" \
TEST_EXPECTED_VERBOSE=""                    \
run_test

# Test 5: CONTAINER_ENV_FILE set to "none" → skip (no args)
CONTAINER_ENV_FILE="none"
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="Env file set to 'none'" \
TEST_EXPECTED_ARGS=""              \
TEST_EXPECTED_VERBOSE=""           \
run_test

# Test 6: CONTAINER_ENV_FILE set to "none" with verbose → skip with message
CONTAINER_ENV_FILE="none"
unset WORKSPACE_PATH
VERBOSE=true
TEST_NAME="Env file 'none' with verbose"                           \
TEST_EXPECTED_ARGS=""                                              \
TEST_EXPECTED_VERBOSE="Skipping --env-file (explicitly disabled)." \
run_test

# Test 7: CONTAINER_ENV_FILE set to custom FILE_NOT_USED token
CONTAINER_ENV_FILE="skip"
FILE_NOT_USED="skip"
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="Custom not_used token" \
TEST_EXPECTED_ARGS=""             \
TEST_EXPECTED_VERBOSE=""          \
run_test

# Test 8: CONTAINER_ENV_FILE set to non-existent file → error
CONTAINER_ENV_FILE="$TEST_DIR/nonexistent.env"
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="Non-existent env file"                       \
TEST_EXPECTED_ERROR="env-file must be an existing file" \
run_error_test

# Test 9: CONTAINER_ENV_FILE set to directory → error
CONTAINER_ENV_FILE="$TEST_DIR"
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="Env file is directory"                       \
TEST_EXPECTED_ERROR="env-file must be an existing file" \
run_error_test

# Test 10: Valid env file with verbose → shows message
CONTAINER_ENV_FILE="$ENV_FILE_2"
unset WORKSPACE_PATH
VERBOSE=true
TEST_NAME="Valid env file with verbose"             \
TEST_EXPECTED_ARGS="--env-file $ENV_FILE_2"         \
TEST_EXPECTED_VERBOSE="Using env-file: $ENV_FILE_2" \
run_test

# Test 11: Empty CONTAINER_ENV_FILE → no args
CONTAINER_ENV_FILE=""
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="Empty CONTAINER_ENV_FILE" \
TEST_EXPECTED_ARGS=""                \
TEST_EXPECTED_VERBOSE=""             \
run_test

# Test 12: WORKSPACE_PATH set but no .env exists → no args
unset CONTAINER_ENV_FILE
WORKSPACE_PATH="$TEST_DIR/no-env-here"
mkdir -p "$WORKSPACE_PATH"
VERBOSE=false
TEST_NAME="Workspace path without .env" \
TEST_EXPECTED_ARGS=""                   \
TEST_EXPECTED_VERBOSE=""                \
run_test

# Test 13: CONTAINER_ENV_FILE overrides workspace default
CONTAINER_ENV_FILE="$ENV_FILE_2"
WORKSPACE_PATH="$WORKSPACE_DIR"
VERBOSE=false
TEST_NAME="Explicit env file overrides default" \
TEST_EXPECTED_ARGS="--env-file $ENV_FILE_2"     \
TEST_EXPECTED_VERBOSE=""                        \
run_test

# Test 14: Multiple calls should append to COMMON_ARGS
unset CONTAINER_ENV_FILE
WORKSPACE_PATH="$WORKSPACE_DIR"
VERBOSE=false
COMMON_ARGS=("--name" "test")
TEST_NAME="Appends to existing COMMON_ARGS"                     \
TEST_EXPECTED_ARGS="--name test --env-file $WORKSPACE_DIR/.env" \
TEST_EXPECTED_VERBOSE=""                                        \
TEST_PRESERVE_COMMON_ARGS=true                                  \
run_test

# Test 15: FILE_NOT_USED unset, CONTAINER_ENV_FILE="none" still works
CONTAINER_ENV_FILE="none"
unset FILE_NOT_USED
unset WORKSPACE_PATH
VERBOSE=false
TEST_NAME="'none' works without FILE_NOT_USED set" \
TEST_EXPECTED_ARGS=""                              \
TEST_EXPECTED_VERBOSE=""                           \
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
