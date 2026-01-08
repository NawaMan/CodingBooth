#!/bin/bash
set -euo pipefail

# Source workspace to get the PopulateArgs function
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

SCRIPT_TITLE=$(script_relative_path "$0")

# Create temporary directory for test files
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  
  test_count=$((test_count + 1))
  
  # Reset all global variables to defaults
  declare -g VERBOSE=false
  declare -g CONFIG_FILE=""
  declare -g SET_CONFIG_FILE=false
  declare -g WORKSPACE_PATH=""
  declare -g DOCKER_FILE=""
  declare -g -a ARGS=()
  
  # Set initial ARGS if provided (must be global array)
  if [[ -n "${TEST_INITIAL_ARGS:-}" ]]; then
    eval "declare -g -a ARGS=(${TEST_INITIAL_ARGS})"
  fi
  
  # Create config file if provided
  local config_file=""
  if [[ -n "${TEST_CONFIG_CONTENT:-}" ]]; then
    config_file="$TEST_DIR/config-$test_count.sh"
    echo "$TEST_CONFIG_CONTENT" > "$config_file"
    # If --config is in ARGS, update it to point to our temp file
    for (( i=0; i<${#ARGS[@]}; i++ )); do
      if [[ "${ARGS[i]}" == "--config" ]]; then
        ARGS[i+1]="$config_file"
        break
      fi
    done
  fi
  
  # Call PopulateArgs (it modifies global ARGS)
  # Can't use command substitution as it creates a subshell
  local output_file="$TEST_DIR/output-$test_count.txt"
  PopulateArgs >"$output_file" 2>&1 || true
  local output=$(cat "$output_file" 2>/dev/null || true)
  
  # Check all expected values
  local all_match=true
  local mismatches=""
  
  for var_check in "${TEST_EXPECTED[@]}"; do
    local var_name="${var_check%%=*}"
    local expected_value="${var_check#*=}"
    
    # Get actual value
    local actual_value=""
    case "$var_name" in
      VERBOSE|SET_CONFIG_FILE)
        actual_value="${!var_name}"
        ;;
      CONFIG_FILE|WORKSPACE_PATH|DOCKER_FILE)
        actual_value="${!var_name}"
        ;;
      ARGS)
        # ARGS might be unset by PopulateArgs, handle carefully
        if declare -p ARGS &>/dev/null; then
          actual_value="${ARGS[*]}"
        else
          actual_value=""
        fi
        ;;
      OUTPUT_CONTAINS)
        # Check if output contains expected string
        if [[ "$output" == *"$expected_value"* ]]; then
          continue
        else
          all_match=false
          mismatches+="  OUTPUT: expected to contain='$expected_value', actual='$output'"$'\n'
          continue
        fi
        ;;
    esac
    
    if [[ "$actual_value" != "$expected_value" ]]; then
      all_match=false
      mismatches+="  $var_name: expected='$expected_value', actual='$actual_value'"$'\n'
    fi
  done
  
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
  
  # Clean up for next test
  unset TEST_INITIAL_ARGS
  unset TEST_CONFIG_CONTENT
}

# Test 1: No arguments
TEST_NAME="No arguments"
TEST_INITIAL_ARGS=""
TEST_EXPECTED=(
  "VERBOSE=false"
  "CONFIG_FILE="
)
run_test

# Test 2: --verbose flag in initial args
TEST_NAME="--verbose flag in initial args"
TEST_INITIAL_ARGS="--verbose"
TEST_EXPECTED=(
  "VERBOSE=true"
  "OUTPUT_CONTAINS=ARGS:"
)
run_test

# Test 3: --config flag sets CONFIG_FILE and SET_CONFIG_FILE
TEST_NAME="--config flag sets variables"
TEST_INITIAL_ARGS="--config /path/to/config"
TEST_EXPECTED=(
  "SET_CONFIG_FILE=true"
)
run_test

# Test 4: --workspace flag
TEST_NAME="--workspace flag"
TEST_INITIAL_ARGS="--workspace /my/workspace"
TEST_EXPECTED=(
  "WORKSPACE_PATH=/my/workspace"
)
run_test

# Test 5: --dockerfile flag
TEST_NAME="--dockerfile flag"
TEST_INITIAL_ARGS="--dockerfile /path/to/Dockerfile"
TEST_EXPECTED=(
  "DOCKER_FILE=/path/to/Dockerfile"
)
run_test

# Test 6: Config file with ARGS array
TEST_NAME="Config file with ARGS array"
TEST_INITIAL_ARGS="--config placeholder"
TEST_CONFIG_CONTENT='ARGS=(--workspace /from/config)'
TEST_EXPECTED=(
  "WORKSPACE_PATH=/from/config"
)
run_test

# Test 7: Config file with variables
TEST_NAME="Config file with variables"
TEST_INITIAL_ARGS="--config placeholder"
TEST_CONFIG_CONTENT='WORKSPACE_PATH=/from/config
DOCKER_FILE=/config/Dockerfile'
TEST_EXPECTED=(
  "WORKSPACE_PATH=/from/config"
  "DOCKER_FILE=/config/Dockerfile"
)
run_test

# Test 8: Config args merged with parameter args
TEST_NAME="Config args merged with parameter args"
TEST_INITIAL_ARGS="--config placeholder --verbose"
TEST_CONFIG_CONTENT='ARGS=(--workspace /from/config)'
TEST_EXPECTED=(
  "VERBOSE=true"
  "WORKSPACE_PATH=/from/config"
)
run_test

# Test 9: Parameter args override config args (last wins)
TEST_NAME="Parameter args override config args"
TEST_INITIAL_ARGS="--config placeholder --workspace /from/params"
TEST_CONFIG_CONTENT='ARGS=(--workspace /from/config)'
TEST_EXPECTED=(
  "WORKSPACE_PATH=/from/params"
)
run_test

# Test 10: Config file with non-array ARGS (should be ignored)
TEST_NAME="Config file with non-array ARGS ignored"
TEST_INITIAL_ARGS="--config placeholder --workspace /from/params"
TEST_CONFIG_CONTENT='ARGS="--workspace /from/config"'
TEST_EXPECTED=(
  "WORKSPACE_PATH=/from/params"
)
run_test

# Test 11: Multiple flags from config
TEST_NAME="Multiple flags from config"
TEST_INITIAL_ARGS="--config placeholder"
TEST_CONFIG_CONTENT='ARGS=(--workspace /ws --dockerfile /df --verbose)'
TEST_EXPECTED=(
  "VERBOSE=true"
  "WORKSPACE_PATH=/ws"
  "DOCKER_FILE=/df"
)
run_test

# Test 12: Config file doesn't exist (no error)
TEST_NAME="Config file doesn't exist"
TEST_INITIAL_ARGS="--config /nonexistent/config --workspace /test"
TEST_EXPECTED=(
  "WORKSPACE_PATH=/test"
  "SET_CONFIG_FILE=true"
)
run_test

# Test 13: Empty config file
TEST_NAME="Empty config file"
TEST_INITIAL_ARGS="--config placeholder --workspace /test"
TEST_CONFIG_CONTENT=""
TEST_EXPECTED=(
  "WORKSPACE_PATH=/test"
)
run_test

# Test 14: Complex realistic scenario
TEST_NAME="Complex realistic scenario"
TEST_INITIAL_ARGS="--config placeholder --verbose --dockerfile /override/Dockerfile"
TEST_CONFIG_CONTENT='WORKSPACE_PATH=/default/workspace
ARGS=(--workspace /config/workspace)'
TEST_EXPECTED=(
  "VERBOSE=true"
  "WORKSPACE_PATH=/config/workspace"
  "DOCKER_FILE=/override/Dockerfile"
)
run_test

# Test 15: --verbose in both config and params
TEST_NAME="--verbose in both config and params"
TEST_INITIAL_ARGS="--config placeholder --verbose"
TEST_CONFIG_CONTENT='ARGS=(--verbose)'
TEST_EXPECTED=(
  "VERBOSE=true"
  "OUTPUT_CONTAINS=ARGS:"
)
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
