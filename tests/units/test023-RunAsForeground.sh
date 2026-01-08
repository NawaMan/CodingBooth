#!/bin/bash
set -euo pipefail

# Source workspace to get the RunAsForeground function
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
  OUTPUT_FILE="$MOCK_DIR/output-$test_count.txt"
  > "$DOCKER_CALLS_FILE"
  
  # Set test variables
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
  SCRIPT_NAME="${TEST_SCRIPT_NAME:-workspace}"
  
  # Call RunAsForeground and capture output
  RunAsForeground > "$OUTPUT_FILE" 2>&1
  
  # Check Docker calls and output
  local actual_calls=$(cat "$DOCKER_CALLS_FILE")
  local actual_output=$(cat "$OUTPUT_FILE")
  local all_match=true
  local mismatches=""
  
  # Check Docker arguments
  for expected_arg in "${TEST_EXPECTED_DOCKER_ARGS[@]}"; do
    if [[ "$actual_calls" != *"$expected_arg"* ]]; then
      all_match=false
      mismatches+="  Missing Docker arg: $expected_arg"$'\n'
    fi
  done
  
  # Check output messages
  for expected_msg in "${TEST_EXPECTED_OUTPUT[@]}"; do
    if [[ "$actual_output" != *"$expected_msg"* ]]; then
      all_match=false
      mismatches+="  Missing output: $expected_msg"$'\n'
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

# Test 1: Basic foreground mode
TEST_NAME="Basic foreground mode"
TEST_TTY_ARGS=("-it")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test-container")
TEST_RUN_ARGS=()
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "-it"
  "--rm"
  "--name test-container"
)
TEST_EXPECTED_OUTPUT=(
  "Running workspace in foreground"
  "Stop with Ctrl+C"
)
run_test

# Test 2: Foreground with custom timezone
TEST_NAME="Foreground with custom timezone"
TEST_TTY_ARGS=("-it")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test")
TEST_RUN_ARGS=()
TEST_TIMEZONE="Europe/London"
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "-e TZ=Europe/London"
)
TEST_EXPECTED_OUTPUT=(
  "Running workspace in foreground"
)
run_test

# Test 3: Foreground with RUN_ARGS
TEST_NAME="Foreground with RUN_ARGS"
TEST_TTY_ARGS=("-it")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test")
TEST_RUN_ARGS=("-v" "/data:/data" "-p" "8080:8080")
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "-it"
  "--rm"
  "-v /data:/data"
  "-p 8080:8080"
)
TEST_EXPECTED_OUTPUT=(
  "Running workspace in foreground"
)
run_test

# Test 4: Foreground with DIND cleanup
TEST_NAME="Foreground with DIND cleanup"
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
TEST_EXPECTED_OUTPUT=(
  "Running workspace in foreground"
)
run_test

# Test 5: Foreground with -i only (no TTY)
TEST_NAME="Foreground with -i only"
TEST_TTY_ARGS=("-i")
TEST_KEEPALIVE_ARGS=("--rm")
TEST_COMMON_ARGS=("--name" "test")
TEST_RUN_ARGS=()
TEST_EXPECTED_DOCKER_ARGS=(
  "run"
  "-i"
  "--rm"
)
TEST_EXPECTED_OUTPUT=(
  "Running workspace in foreground"
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
