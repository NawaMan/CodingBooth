#!/bin/bash
set -euo pipefail

# Source workspace to get the PrepareCommonArgs function
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
  
  # Reset COMMON_ARGS
  COMMON_ARGS=()
  
  # Set required variables
  CONTAINER_NAME="${TEST_CONTAINER_NAME:-test-container}"
  HOST_UID="${TEST_HOST_UID:-1000}"
  HOST_GID="${TEST_HOST_GID:-1000}"
  WORKSPACE_PATH="${TEST_WORKSPACE_PATH:-/test/workspace}"
  HOST_PORT="${TEST_HOST_PORT:-10000}"
  SETUPS_DIR="${TEST_SETUPS_DIR:-/setups}"
  DAEMON="${TEST_DAEMON:-false}"
  IMAGE_NAME="${TEST_IMAGE_NAME:-test-image}"
  RUN_MODE="${TEST_RUN_MODE:-interactive}"
  VARIANT="${TEST_VARIANT:-base}"
  VERBOSE="${TEST_VERBOSE:-false}"
  VERSION="${TEST_VERSION:-latest}"
  WORKSPACE_PORT="${TEST_WORKSPACE_PORT:-10000}"
  HAS_NOTEBOOK="${TEST_HAS_NOTEBOOK:-false}"
  HAS_VSCODE="${TEST_HAS_VSCODE:-false}"
  HAS_DESKTOP="${TEST_HAS_DESKTOP:-false}"
  DO_PULL="${TEST_DO_PULL:-false}"
  
  # Call PrepareCommonArgs
  PrepareCommonArgs
  
  # Check results
  local all_match=true
  local mismatches=""
  local args_string="${COMMON_ARGS[*]}"
  
  for expected_arg in "${TEST_EXPECTED_ARGS[@]}"; do
    if [[ "$args_string" != *"$expected_arg"* ]]; then
      all_match=false
      mismatches+="  Missing expected arg: $expected_arg"$'\n'
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
}

# Test 1: Basic configuration
TEST_NAME="Basic configuration"
TEST_CONTAINER_NAME="my-container"
TEST_HOST_PORT="8080"
TEST_WORKSPACE_PATH="/my/workspace"
TEST_EXPECTED_ARGS=(
  "--name my-container"
  "-e HOST_UID=1000"
  "-e HOST_GID=1000"
  "-v /my/workspace:/home/coder/workspace"
  "-w /home/coder/workspace"
  "-p 8080:10000"
)
run_test

# Test 2: With DO_PULL=false (should add --pull=never)
TEST_NAME="With DO_PULL=false"
TEST_CONTAINER_NAME="test-container"
TEST_DO_PULL="false"
TEST_EXPECTED_ARGS=(
  "--name test-container"
  "--pull=never"
)
run_test

# Test 3: With DO_PULL=true (should NOT add --pull=never)
TEST_NAME="With DO_PULL=true"
TEST_CONTAINER_NAME="test-container"
TEST_DO_PULL="true"
TEST_EXPECTED_ARGS=(
  "--name test-container"
)
run_test

# Test 4: Metadata environment variables
TEST_NAME="Metadata environment variables"
TEST_VARIANT="ide-codeserver"
TEST_VERSION="v1.0.0"
TEST_HAS_NOTEBOOK="true"
TEST_HAS_VSCODE="true"
TEST_HAS_DESKTOP="false"
TEST_EXPECTED_ARGS=(
  "-e WS_VARIANT_TAG=ide-codeserver"
  "-e WS_VERSION_TAG=v1.0.0"
  "-e WS_HAS_NOTEBOOK=true"
  "-e WS_HAS_VSCODE=true"
  "-e WS_HAS_DESKTOP=false"
)
run_test

# Test 5: DAEMON mode
TEST_NAME="DAEMON mode"
TEST_DAEMON="true"
TEST_EXPECTED_ARGS=(
  "-e WS_DAEMON=true"
)
run_test

# Test 6: VERBOSE mode
TEST_NAME="VERBOSE mode"
TEST_VERBOSE="true"
TEST_EXPECTED_ARGS=(
  "-e WS_VERBOSE=true"
)
run_test

# Test 7: Custom SETUPS_DIR
TEST_NAME="Custom SETUPS_DIR"
TEST_SETUPS_DIR="/custom/setups"
TEST_EXPECTED_ARGS=(
  "-e WS_SETUPS_DIR=/custom/setups"
)
run_test

# Test 8: All metadata variables
TEST_NAME="All metadata variables"
TEST_CONTAINER_NAME="full-test"
TEST_HOST_PORT="9000"
TEST_IMAGE_NAME="myimage:tag"
TEST_RUN_MODE="daemon"
TEST_WORKSPACE_PORT="NEXT"
TEST_EXPECTED_ARGS=(
  "-e WS_CONTAINER_NAME=full-test"
  "-e WS_HOST_PORT=9000"
  "-e WS_IMAGE_NAME=myimage:tag"
  "-e WS_RUNMODE=daemon"
  "-e WS_WORKSPACE_PORT=NEXT"
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
