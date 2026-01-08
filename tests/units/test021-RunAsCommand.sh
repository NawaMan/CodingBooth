#!/bin/bash
set -euo pipefail

# Source workspace to get the RunAsCommand function
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
  return 0
}

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  
  test_count=$((test_count + 1))
  
  # Reset variables
  DOCKER_CALLS_FILE="$MOCK_DIR/docker-calls-$test_count.txt"
  > "$DOCKER_CALLS_FILE"
  
  # Set test variables
  CMDS=()
  if [[ -n "${TEST_CMDS:-}" ]]; then
    eval "CMDS=(${TEST_CMDS})"
  fi
  TTY_ARGS=("${TEST_TTY_ARGS[@]}")
  KEEPALIVE_ARGS=("${TEST_KEEPALIVE_ARGS[@]}")
  COMMON_ARGS=("${TEST_COMMON_ARGS[@]}")
  RUN_ARGS=("${TEST_RUN_ARGS[@]}")
  TIMEZONE="${TEST_TIMEZONE:-UTC}"
  IMAGE_NAME="${TEST_IMAGE_NAME:-test-image:latest}"
  DIND="${TEST_DIND:-false}"
  DIND_NAME="${TEST_DIND_NAME:-dind-container}"
  DIND_NET="${TEST_DIND_NET:-dind-network}"
  CREATED_DIND_NET="${TEST_CREATED_DIND_NET:-false}"
  
  # Call RunAsCommand
  RunAsCommand >/dev/null 2>&1
  
  # Check Docker calls
  local actual_calls=$(cat "$DOCKER_CALLS_FILE")
  local all_match=true
  local mismatches=""
  
  for expected_arg in "${TEST_EXPECTED_DOCKER_ARGS[@]}"; do
    if [[ "$actual_calls" != *"$expected_arg"* ]]; then
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
    echo "Actual calls:"
    cat "$DOCKER_CALLS_FILE"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: Basic command execution
TEST_NAME="Basic command execution"
TEST_CMDS="'echo' 'hello'"
TEST_TTY_ARGS=("-it")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test-container")
TEST_RUN_ARGS=()
TEST_IMAGE_NAME="ubuntu:latest"
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "-it"
  "--rm"
  "--name test-container"
  "ubuntu:latest"
  "bash -lc"
  "echo hello"
)
run_test

# Test 2: With custom timezone
TEST_NAME="With custom timezone"
TEST_CMDS="'date'"
TEST_TTY_ARGS=("-i")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test")
TEST_RUN_ARGS=()
TEST_TIMEZONE="America/New_York"
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "-e TZ=America/New_York"
)
run_test

# Test 3: With RUN_ARGS
TEST_NAME="With RUN_ARGS"
TEST_CMDS="'ls'"
TEST_TTY_ARGS=("-it")
TEST_KEEPALIVE_ARGS=()
TEST_COMMON_ARGS=("--name" "test")
TEST_RUN_ARGS=("-v" "/data:/data")
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "-it"
  "--name test"
  "-v /data:/data"
)
run_test

# Test 4: With DIND enabled
TEST_NAME="With DIND enabled (cleanup)"
TEST_CMDS="'echo' 'test'"
TEST_TTY_ARGS=("-it")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test")
TEST_RUN_ARGS=()
TEST_DIND="true"
TEST_DIND_NAME="dind-sidecar"
TEST_DIND_NET="dind-net"
TEST_CREATED_DIND_NET="true"
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "stop dind-sidecar"
  "network rm dind-net"
)
run_test

# Test 5: Multiple commands
TEST_NAME="Multiple commands"
TEST_CMDS="'echo' 'hello' '&&' 'echo' 'world'"
TEST_TTY_ARGS=("-it")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test")
TEST_RUN_ARGS=()
TEST_EXPECTED_DOCKER_ARGS=(
  "bash -lc"
  "echo hello && echo world"
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
