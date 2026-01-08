#!/bin/bash
set -euo pipefail

# Source workspace to get the ParseArgs function
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
  local test_args=("${TEST_ARGS[@]}")
  
  test_count=$((test_count + 1))
  
  # Reset all variables to defaults
  DRYRUN=false
  VERBOSE=false
  DO_PULL=false
  DAEMON=false
  KEEPALIVE=false
  DIND=false
  CONFIG_FILE=""
  WORKSPACE_PATH=""
  IMAGE_NAME=""
  VARIANT=""
  VERSION=""
  DOCKER_FILE=""
  BUILD_ARGS=()
  SILENCE_BUILD=false
  CONTAINER_NAME=""
  WORKSPACE_PORT=""
  CONTAINER_ENV_FILE=""
  RUN_ARGS=()
  CMDS=()
  
  # Parse arguments
  ParseArgs "${test_args[@]}"
  
  # Check all expected values
  local all_match=true
  local mismatches=""
  
  for var_check in "${TEST_EXPECTED[@]}"; do
    local var_name="${var_check%%=*}"
    local expected_value="${var_check#*=}"
    
    # Get actual value
    local actual_value=""
    case "$var_name" in
      DRYRUN|VERBOSE|DO_PULL|DAEMON|KEEPALIVE|DIND|SILENCE_BUILD)
        actual_value="${!var_name}"
        ;;
      CONFIG_FILE|WORKSPACE_PATH|IMAGE_NAME|VARIANT|VERSION|DOCKER_FILE|CONTAINER_NAME|WORKSPACE_PORT|CONTAINER_ENV_FILE)
        actual_value="${!var_name}"
        ;;
      BUILD_ARGS)
        actual_value="${BUILD_ARGS[*]}"
        ;;
      RUN_ARGS)
        actual_value="${RUN_ARGS[*]}"
        ;;
      CMDS)
        actual_value="${CMDS[*]}"
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
}

# Test 1: Boolean flags
TEST_NAME="Boolean flags"
TEST_ARGS=(--dryrun --verbose --pull --daemon --keep-alive --dind)
TEST_EXPECTED=(
  "DRYRUN=true"
  "VERBOSE=true"
  "DO_PULL=true"
  "DAEMON=true"
  "KEEPALIVE=true"
  "DIND=true"
)
run_test

# Test 2: --config flag
TEST_NAME="--config flag"
TEST_ARGS=(--config /path/to/config)
TEST_EXPECTED=(
  "CONFIG_FILE=/path/to/config"
)
run_test

# Test 3: --workspace flag
TEST_NAME="--workspace flag"
TEST_ARGS=(--workspace /path/to/workspace)
TEST_EXPECTED=(
  "WORKSPACE_PATH=/path/to/workspace"
)
run_test

# Test 4: --image flag
TEST_NAME="--image flag"
TEST_ARGS=(--image myimage:latest)
TEST_EXPECTED=(
  "IMAGE_NAME=myimage:latest"
)
run_test

# Test 5: --variant flag
TEST_NAME="--variant flag"
TEST_ARGS=(--variant base)
TEST_EXPECTED=(
  "VARIANT=base"
)
run_test

# Test 6: --version flag
TEST_NAME="--version flag"
TEST_ARGS=(--version v1.0.0)
TEST_EXPECTED=(
  "VERSION=v1.0.0"
)
run_test

# Test 7: --dockerfile flag
TEST_NAME="--dockerfile flag"
TEST_ARGS=(--dockerfile /path/to/Dockerfile)
TEST_EXPECTED=(
  "DOCKER_FILE=/path/to/Dockerfile"
)
run_test

# Test 8: --build-arg flag (single)
TEST_NAME="--build-arg flag (single)"
TEST_ARGS=(--build-arg KEY=value)
TEST_EXPECTED=(
  "BUILD_ARGS=--build-arg KEY=value"
)
run_test

# Test 9: --build-arg flag (multiple)
TEST_NAME="--build-arg flag (multiple)"
TEST_ARGS=(--build-arg KEY1=value1 --build-arg KEY2=value2)
TEST_EXPECTED=(
  "BUILD_ARGS=--build-arg KEY1=value1 --build-arg KEY2=value2"
)
run_test

# Test 10: --silence-build flag
TEST_NAME="--silence-build flag"
TEST_ARGS=(--silence-build)
TEST_EXPECTED=(
  "SILENCE_BUILD=true"
)
run_test

# Test 11: --name flag
TEST_NAME="--name flag"
TEST_ARGS=(--name my-container)
TEST_EXPECTED=(
  "CONTAINER_NAME=my-container"
)
run_test

# Test 12: --port flag
TEST_NAME="--port flag"
TEST_ARGS=(--port 8080)
TEST_EXPECTED=(
  "WORKSPACE_PORT=8080"
)
run_test

# Test 13: --env-file flag
TEST_NAME="--env-file flag"
TEST_ARGS=(--env-file /path/to/.env)
TEST_EXPECTED=(
  "CONTAINER_ENV_FILE=/path/to/.env"
)
run_test

# Test 14: Unknown args go to RUN_ARGS
TEST_NAME="Unknown args go to RUN_ARGS"
TEST_ARGS=(--unknown-flag -v /host:/container)
TEST_EXPECTED=(
  "RUN_ARGS=--unknown-flag -v /host:/container"
)
run_test

# Test 15: -- separator for CMDS
TEST_NAME="-- separator for CMDS"
TEST_ARGS=(-- echo hello world)
TEST_EXPECTED=(
  "CMDS=echo hello world"
)
run_test

# Test 16: Mixed args before --
TEST_NAME="Mixed args before --"
TEST_ARGS=(--verbose --name test -- bash -c "echo test")
TEST_EXPECTED=(
  "VERBOSE=true"
  "CONTAINER_NAME=test"
  "CMDS=bash -c echo test"
)
run_test

# Test 17: RUN_ARGS and CMDS
TEST_NAME="RUN_ARGS and CMDS"
TEST_ARGS=(-v /data:/data --dryrun -- ls -la)
TEST_EXPECTED=(
  "DRYRUN=true"
  "RUN_ARGS=-v /data:/data"
  "CMDS=ls -la"
)
run_test

# Test 18: Complex realistic example
TEST_NAME="Complex realistic example"
TEST_ARGS=(
  --verbose
  --workspace /my/workspace
  --variant ide-codeserver
  --version latest
  --name my-dev-env
  --port 8080
  --env-file .env
  --build-arg VERSION=1.0
  -v /data:/data
  --
  bash
)
TEST_EXPECTED=(
  "VERBOSE=true"
  "WORKSPACE_PATH=/my/workspace"
  "VARIANT=ide-codeserver"
  "VERSION=latest"
  "CONTAINER_NAME=my-dev-env"
  "WORKSPACE_PORT=8080"
  "CONTAINER_ENV_FILE=.env"
  "BUILD_ARGS=--build-arg VERSION=1.0"
  "RUN_ARGS=-v /data:/data"
  "CMDS=bash"
)
run_test

# Test 19: Empty args
TEST_NAME="Empty args"
TEST_ARGS=()
TEST_EXPECTED=(
  "DRYRUN=false"
  "VERBOSE=false"
)
run_test

# Test 20: Args with spaces
TEST_NAME="Args with spaces"
TEST_ARGS=(--name "my container" --workspace "/path with spaces")
TEST_EXPECTED=(
  "CONTAINER_NAME=my container"
  "WORKSPACE_PATH=/path with spaces"
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
echo ""
echo "NOTE: Error cases (missing required values) are not tested because the"
echo "      function calls 'exit 1' which would terminate this script."
echo "==============================================================================="

if [ $fail_count -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed!"
  exit 1
fi
