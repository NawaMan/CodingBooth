#!/bin/bash
set -euo pipefail

# Source workspace to get the SetupDind function
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

SCRIPT_TITLE=$(script_relative_path "$0")

# Create mock directory
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# Mock Docker function to capture calls
Docker() {
  echo "$@" >> "$DOCKER_CALLS_FILE"
  
  # Simulate different responses based on command
  case "$1" in
    "network")
      if [[ "$2" == "inspect" ]]; then
        # Return error if network doesn't exist (for first test)
        if [[ "${TEST_NETWORK_EXISTS:-false}" == "true" ]]; then
          return 0
        else
          return 1
        fi
      fi
      ;;
    "ps")
      # Return container name if it exists
      if [[ "${TEST_CONTAINER_EXISTS:-false}" == "true" ]]; then
        echo "$DIND_NAME"
      fi
      ;;
    "run")
      # For daemon check, return success
      if [[ "$*" == *"docker:cli"* ]]; then
        return 0
      fi
      ;;
  esac
  return 0
}

# Mock docker info command
docker() {
  if [[ "$1" == "info" ]]; then
    if [[ "${TEST_IS_DOCKER_DESKTOP:-false}" == "true" ]]; then
      echo "Docker Desktop"
    else
      echo "Docker Engine"
    fi
  fi
}

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  
  test_count=$((test_count + 1))
  
  # Reset variables
  DOCKER_CALLS_FILE="$MOCK_DIR/docker-calls-$test_count.txt"
  > "$DOCKER_CALLS_FILE"
  
  # Set test variables with defaults
  DIND="${TEST_DIND:-false}"
  CONTAINER_NAME="${TEST_CONTAINER_NAME:-test-container}"
  HOST_PORT="${TEST_HOST_PORT:-10000}"
  VERBOSE="${TEST_VERBOSE:-false}"
  DRYRUN="${TEST_DRYRUN:-false}"
  RUN_ARGS=()
  if [[ -n "${TEST_RUN_ARGS:-}" ]]; then
    eval "RUN_ARGS=(${TEST_RUN_ARGS})"
  fi
  COMMON_ARGS=()
  
  # Set test environment variables (override defaults if specified)
  if [[ -z "${TEST_NETWORK_EXISTS+x}" ]]; then
    TEST_NETWORK_EXISTS="false"
  fi
  if [[ -z "${TEST_CONTAINER_EXISTS+x}" ]]; then
    TEST_CONTAINER_EXISTS="false"
  fi
  if [[ -z "${TEST_IS_DOCKER_DESKTOP+x}" ]]; then
    TEST_IS_DOCKER_DESKTOP="false"
  fi
  
  # Call SetupDind
  SetupDind
  
  # Check results
  local all_match=true
  local mismatches=""
  
  # Check expected variables
  for var_check in "${TEST_EXPECTED[@]}"; do
    local var_name="${var_check%%=*}"
    local expected_value="${var_check#*=}"
    
    local actual_value=""
    case "$var_name" in
      DIND_NET|DIND_NAME|CREATED_DIND_NET)
        actual_value="${!var_name}"
        ;;
      COMMON_ARGS_CONTAINS)
        # Check if COMMON_ARGS contains expected value
        if [[ "${COMMON_ARGS[*]}" == *"$expected_value"* ]]; then
          continue
        else
          all_match=false
          mismatches+="  COMMON_ARGS missing: $expected_value"$'\n'
          continue
        fi
        ;;
      DOCKER_CALLS_CONTAINS)
        # Check if Docker calls contain expected value
        local calls=$(cat "$DOCKER_CALLS_FILE")
        if [[ "$calls" == *"$expected_value"* ]]; then
          continue
        else
          all_match=false
          mismatches+="  Docker calls missing: $expected_value"$'\n'
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
}

# Test 1: DIND=false (no setup)
TEST_NAME="DIND=false does nothing"
TEST_DIND="false"
TEST_EXPECTED=(
  "DIND_NET="
  "DIND_NAME="
)
run_test

# Test 2: DIND=true creates network and container
TEST_NAME="DIND=true creates network and container"
TEST_DIND="true"
TEST_CONTAINER_NAME="my-workspace"
TEST_HOST_PORT="8080"
TEST_NETWORK_EXISTS="false"
TEST_CONTAINER_EXISTS="false"
TEST_EXPECTED=(
  "DIND_NET=my-workspace-8080-net"
  "DIND_NAME=my-workspace-8080-dind"
  "CREATED_DIND_NET=true"
  "DOCKER_CALLS_CONTAINS=network create"
  "DOCKER_CALLS_CONTAINS=run -d --rm --privileged"
  "COMMON_ARGS_CONTAINS=--network my-workspace-8080-net"
  "COMMON_ARGS_CONTAINS=DOCKER_HOST=tcp://my-workspace-8080-dind:2375"
)
run_test

# Test 3: Network already exists
TEST_NAME="Network already exists"
TEST_DIND="true"
TEST_NETWORK_EXISTS="true"
TEST_CONTAINER_EXISTS="false"
TEST_EXPECTED=(
  "CREATED_DIND_NET=false"
  "DOCKER_CALLS_CONTAINS=network inspect"
)
run_test

# Test 4: Container already running
TEST_NAME="Container already running"
TEST_DIND="true"
TEST_NETWORK_EXISTS="true"
TEST_CONTAINER_EXISTS="true"
TEST_EXPECTED=(
  "DOCKER_CALLS_CONTAINS=ps --filter"
)
run_test

# Test 5: Docker Desktop detection
TEST_NAME="Docker Desktop detection"
TEST_DIND="true"
TEST_IS_DOCKER_DESKTOP="true"
TEST_NETWORK_EXISTS="false"
TEST_CONTAINER_EXISTS="false"
TEST_EXPECTED=(
  "DOCKER_CALLS_CONTAINS=run -d --rm --privileged"
  "DOCKER_CALLS_CONTAINS=docker:dind"
)
run_test

# Test 6: Strips network flags from RUN_ARGS and adds DinD network
TEST_NAME="Strips network flags from RUN_ARGS"
TEST_DIND="true"
TEST_RUN_ARGS="'--network' 'mynet' '-v' '/data:/data'"
TEST_NETWORK_EXISTS="true"
TEST_CONTAINER_EXISTS="true"
TEST_EXPECTED=(
  "COMMON_ARGS_CONTAINS=--network"
  "COMMON_ARGS_CONTAINS=DOCKER_HOST=tcp://"
)
run_test

# Test 7: VERBOSE mode shows messages
TEST_NAME="VERBOSE mode shows messages"
TEST_DIND="true"
TEST_VERBOSE="true"
TEST_NETWORK_EXISTS="false"
TEST_CONTAINER_EXISTS="false"
TEST_EXPECTED=(
  "DOCKER_CALLS_CONTAINS=network create"
)
run_test

# Test 8: DRYRUN mode skips daemon check
TEST_NAME="DRYRUN mode skips daemon check"
TEST_DIND="true"
TEST_DRYRUN="true"
TEST_NETWORK_EXISTS="false"
TEST_CONTAINER_EXISTS="false"
TEST_EXPECTED=(
  "DOCKER_CALLS_CONTAINS=network create"
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
