#!/bin/bash
set -euo pipefail

# Source workspace to get the EnsureDockerImage function
# Set SKIP_MAIN to prevent the main script from executing
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

# Mock DockerBuild function
DockerBuild() {
  echo "DockerBuild $*" >> "$DOCKER_BUILD_CALLS_FILE"
  return ${DOCKER_BUILD_EXIT_CODE:-0}
}

# Mock Docker function
Docker() {
  echo "Docker $*" >> "$DOCKER_CALLS_FILE"
  
  # Handle specific docker commands
  if [[ "$1" == "image" && "$2" == "inspect" ]]; then
    # Check if image should exist
    local image_name="$3"
    if [[ " ${EXISTING_IMAGES[@]:-} " =~ " ${image_name} " ]]; then
      return 0
    else
      return 1
    fi
  elif [[ "$1" == "pull" ]]; then
    # Simulate pull success/failure
    return ${DOCKER_PULL_EXIT_CODE:-0}
  fi
  
  return ${DOCKER_EXIT_CODE:-0}
}

# Export mocked functions
export -f DockerBuild
export -f Docker

# Files to track calls
DOCKER_BUILD_CALLS_FILE=$(mktemp)
DOCKER_CALLS_FILE=$(mktemp)
trap 'rm -f "$DOCKER_BUILD_CALLS_FILE" "$DOCKER_CALLS_FILE"' EXIT

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  local expected_image_mode="$TEST_EXPECTED_IMAGE_MODE"
  local expected_image_name="$TEST_EXPECTED_IMAGE_NAME"
  local expected_build_calls="${TEST_EXPECTED_BUILD_CALLS:-}"
  local expected_docker_calls="${TEST_EXPECTED_DOCKER_CALLS:-}"
  
  test_count=$((test_count + 1))
  
  # Reset call tracking
  > "$DOCKER_BUILD_CALLS_FILE"
  > "$DOCKER_CALLS_FILE"
  export DOCKER_BUILD_EXIT_CODE=0
  export DOCKER_EXIT_CODE=0
  export DOCKER_PULL_EXIT_CODE=0
  
  # Call function
  EnsureDockerImage >/dev/null 2>&1
  
  # Read actual calls
  local actual_build_calls=""
  local actual_docker_calls=""
  [[ -s "$DOCKER_BUILD_CALLS_FILE" ]] && actual_build_calls=$(cat "$DOCKER_BUILD_CALLS_FILE")
  [[ -s "$DOCKER_CALLS_FILE" ]] && actual_docker_calls=$(cat "$DOCKER_CALLS_FILE")
  
  # Check results
  local mode_match=false
  local name_match=false
  local build_calls_match=false
  local docker_calls_match=false
  
  [[ "${IMAGE_MODE:-}" == "$expected_image_mode" ]] && mode_match=true
  [[ "${IMAGE_NAME:-}" == "$expected_image_name" ]] && name_match=true
  
  if [[ -z "$expected_build_calls" ]]; then
    [[ -z "$actual_build_calls" ]] && build_calls_match=true
  else
    [[ "$actual_build_calls" == *"$expected_build_calls"* ]] && build_calls_match=true
  fi
  
  if [[ -z "$expected_docker_calls" ]]; then
    [[ -z "$actual_docker_calls" ]] && docker_calls_match=true
  else
    [[ "$actual_docker_calls" == *"$expected_docker_calls"* ]] && docker_calls_match=true
  fi
  
  if $mode_match && $name_match && $build_calls_match && $docker_calls_match; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    ! $mode_match && echo "  IMAGE_MODE: expected=$expected_image_mode, actual=${IMAGE_MODE:-}"
    ! $name_match && echo "  IMAGE_NAME: expected=$expected_image_name, actual=${IMAGE_NAME:-}"
    ! $build_calls_match && echo "  Build calls: expected='$expected_build_calls', actual='$actual_build_calls'"
    ! $docker_calls_match && echo "  Docker calls: expected='$expected_docker_calls', actual='$actual_docker_calls'"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Setup test environment
mkdir -p "$TEST_DIR/workspace"
echo "FROM ubuntu" > "$TEST_DIR/workspace/ws--Dockerfile"

# Test 1: EXISTING mode - IMAGE_NAME provided
unset DOCKER_FILE
unset WORKSPACE_PATH
IMAGE_NAME="myimage:latest"
EXISTING_IMAGES=("myimage:latest")
DRYRUN=false
DO_PULL=false
SILENCE_BUILD=true
VERBOSE=false
TEST_NAME="EXISTING mode with IMAGE_NAME"                \
TEST_EXPECTED_IMAGE_MODE="EXISTING"                      \
TEST_EXPECTED_IMAGE_NAME="myimage:latest"                \
TEST_EXPECTED_BUILD_CALLS=""                             \
TEST_EXPECTED_DOCKER_CALLS="Docker image inspect"        \
run_test

# Test 2: LOCAL-BUILD mode - DOCKER_FILE provided
unset IMAGE_NAME
DOCKER_FILE="$TEST_DIR/workspace/ws--Dockerfile"
WORKSPACE_PATH="$TEST_DIR/workspace"
PROJECT_NAME="testproject"
VARIANT="base"
VERSION="latest"
SETUPS_DIR="/setups"
HAS_NOTEBOOK="false"
HAS_VSCODE="false"
HAS_DESKTOP="false"
BUILD_ARGS=()
EXISTING_IMAGES=("workspace-local:testproject-base-latest")
TEST_NAME="LOCAL-BUILD mode with DOCKER_FILE"                           \
TEST_EXPECTED_IMAGE_MODE="LOCAL-BUILD"                                  \
TEST_EXPECTED_IMAGE_NAME="workspace-local:testproject-base-latest"      \
TEST_EXPECTED_BUILD_CALLS="DockerBuild -f"                              \
TEST_EXPECTED_DOCKER_CALLS="Docker image inspect"                       \
run_test

# Test 3: LOCAL-BUILD - DOCKER_FILE as directory
unset IMAGE_NAME
DOCKER_FILE="$TEST_DIR/workspace"
WORKSPACE_PATH="$TEST_DIR/workspace"
EXISTING_IMAGES=("workspace-local:testproject-base-latest")
TEST_NAME="LOCAL-BUILD with DOCKER_FILE as directory"                   \
TEST_EXPECTED_IMAGE_MODE="LOCAL-BUILD"                                  \
TEST_EXPECTED_IMAGE_NAME="workspace-local:testproject-base-latest"      \
TEST_EXPECTED_BUILD_CALLS="DockerBuild -f"                              \
TEST_EXPECTED_DOCKER_CALLS="Docker image inspect"                       \
run_test

# Test 4: LOCAL-BUILD - auto-detect ws--Dockerfile
unset IMAGE_NAME
unset DOCKER_FILE
WORKSPACE_PATH="$TEST_DIR/workspace"
EXISTING_IMAGES=("workspace-local:testproject-base-latest")
TEST_NAME="LOCAL-BUILD auto-detect ws--Dockerfile"                      \
TEST_EXPECTED_IMAGE_MODE="LOCAL-BUILD"                                  \
TEST_EXPECTED_IMAGE_NAME="workspace-local:testproject-base-latest"      \
TEST_EXPECTED_BUILD_CALLS="DockerBuild -f"                              \
TEST_EXPECTED_DOCKER_CALLS="Docker image inspect"                       \
run_test

# Test 5: PREBUILT mode
unset IMAGE_NAME
unset DOCKER_FILE
WORKSPACE_PATH="$TEST_DIR/empty"
mkdir -p "$TEST_DIR/empty"
PREBUILD_REPO="nawaman/workspace"
EXISTING_IMAGES=("nawaman/workspace:base-latest")
TEST_NAME="PREBUILT mode"                                               \
TEST_EXPECTED_IMAGE_MODE="PREBUILT"                                     \
TEST_EXPECTED_IMAGE_NAME="nawaman/workspace:base-latest"                \
TEST_EXPECTED_BUILD_CALLS=""                                            \
TEST_EXPECTED_DOCKER_CALLS="Docker image inspect"                       \
run_test

# Test 6: PREBUILT with --pull flag
unset IMAGE_NAME
unset DOCKER_FILE
WORKSPACE_PATH="$TEST_DIR/empty"
PROJECT_NAME="testproject"
VARIANT="base"
VERSION="latest"
PREBUILD_REPO="nawaman/workspace"
DRYRUN=false
SILENCE_BUILD=true
unset IMAGE_NAME
unset DOCKER_FILE
WORKSPACE_PATH="$TEST_DIR/empty"
PROJECT_NAME="testproject"
VARIANT="base"
VERSION="latest"
PREBUILD_REPO="nawaman/workspace"
SILENCE_BUILD=true
VERBOSE=false
VERBOSE=false
DO_PULL=true
EXISTING_IMAGES=("nawaman/workspace:base-latest")
TEST_NAME="PREBUILT with --pull flag"                                   \
TEST_EXPECTED_IMAGE_MODE="PREBUILT"                                     \
TEST_EXPECTED_IMAGE_NAME="nawaman/workspace:base-latest"                \
TEST_EXPECTED_DOCKER_CALLS="Docker pull"                                \
run_test

# Test 7: DRYRUN mode
unset IMAGE_NAME
unset DOCKER_FILE
WORKSPACE_PATH="$TEST_DIR/empty"
PROJECT_NAME="testproject"
VARIANT="base"
VERSION="latest"
PREBUILD_REPO="nawaman/workspace"
SILENCE_BUILD=true
VERBOSE=false
DO_PULL=false
DRYRUN=true
EXISTING_IMAGES=()
TEST_NAME="DRYRUN mode skips image checks"                              \
TEST_EXPECTED_IMAGE_MODE="PREBUILT"                                     \
TEST_EXPECTED_IMAGE_NAME="nawaman/workspace:base-latest"                \
TEST_EXPECTED_DOCKER_CALLS=""                                           \
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
echo "NOTE: Error cases (non-existent DOCKER_FILE, pull failures) are not tested"
echo "      because the function calls 'exit 1' which would terminate this script."
echo "==============================================================================="

if [ $fail_count -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed!"
  exit 1
fi
