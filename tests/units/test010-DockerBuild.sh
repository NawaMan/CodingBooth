#!/bin/bash
set -euo pipefail

# Source workspace to get the DockerBuild function
# Set SKIP_MAIN to prevent the main script from executing
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

# Create a temporary directory for our mock docker
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# Create mock docker script that can simulate success or failure
cat > "$MOCK_DIR/docker" << 'MOCK_SCRIPT'
#!/bin/bash
# Mock docker - logs calls and can simulate failures
echo "$@" >> "$DOCKER_CALLS_FILE"

# Check if we should fail
if [[ "${DOCKER_SHOULD_FAIL:-false}" == "true" ]]; then
  echo "Error: simulated docker build failure" >&2
  exit 1
fi

exit 0
MOCK_SCRIPT

chmod +x "$MOCK_DIR/docker"

# Add mock to PATH (prepend so it takes precedence)
export PATH="$MOCK_DIR:$PATH"

# Clear bash's command hash table so it finds our mock
hash -r

# File to track docker calls
DOCKER_CALLS_FILE=$(mktemp)
trap 'rm -f "$DOCKER_CALLS_FILE"' EXIT
export DOCKER_CALLS_FILE

# Variable to control mock behavior
export DOCKER_SHOULD_FAIL=false

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  local expected_exit_code="$TEST_EXPECTED_EXIT"
  local expected_output_pattern="$TEST_EXPECTED_OUTPUT_PATTERN"
  local expected_calls="$TEST_EXPECTED_CALLS"
  local should_fail="${TEST_DOCKER_SHOULD_FAIL:-false}"
  
  test_count=$((test_count + 1))
  
  # Reset docker calls file and set mock behavior
  > "$DOCKER_CALLS_FILE"
  export DOCKER_SHOULD_FAIL="$should_fail"
  
  # Capture output and exit code
  local actual_output
  local actual_exit_code
  set +e
  actual_output=$(DockerBuild "$@" 2>&1)
  actual_exit_code=$?
  set -e
  
  # Read calls from file
  local actual_calls
  if [[ -s "$DOCKER_CALLS_FILE" ]]; then
    actual_calls=$(cat "$DOCKER_CALLS_FILE")
  else
    actual_calls=""
  fi
  
  # Check exit code and output pattern
  local exit_match=false
  local output_match=false
  local calls_match=false
  
  if [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
    exit_match=true
  fi
  
  if [[ -z "$expected_output_pattern" ]] || [[ "$actual_output" == *"$expected_output_pattern"* ]]; then
    output_match=true
  fi

  if diff -u <(echo "$expected_calls") <(echo "$actual_calls") >/dev/null 2>&1; then
    calls_match=true
  fi
  
  if $exit_match && $output_match && $calls_match; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    if ! $exit_match; then
      echo "Exit code mismatch:"
      echo "  Expected: $expected_exit_code"
      echo "  Actual:   $actual_exit_code"
    fi
    if ! $output_match; then
      echo "Output pattern not found:"
      echo "  Expected pattern: $expected_output_pattern"
      echo "  Actual output:"
      echo "$actual_output"
    fi
    if ! $calls_match; then
      echo "Docker calls mismatch:"
      echo "  Expected: $expected_calls"
      echo "  Actual:   $actual_calls"
    fi
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: Normal build (SILENCE_BUILD=false)
SILENCE_BUILD=false
DRYRUN=false
VERBOSE=false
TEST_NAME="Normal build without silence"        \
TEST_EXPECTED_EXIT=0                            \
TEST_EXPECTED_OUTPUT_PATTERN=""                 \
TEST_EXPECTED_CALLS="build -t myimage:latest ." \
run_test -t myimage:latest .

# Test 2: Silent build success (SILENCE_BUILD=true)
SILENCE_BUILD=true
DRYRUN=false
VERBOSE=false
TEST_NAME="Silent build success"                \
TEST_EXPECTED_EXIT=0                            \
TEST_EXPECTED_OUTPUT_PATTERN=""                 \
TEST_EXPECTED_CALLS="build -t myimage:latest ." \
run_test -t myimage:latest .

# Test 3: Silent build failure (SILENCE_BUILD=true, build fails)
SILENCE_BUILD=true
DRYRUN=false
VERBOSE=false
TEST_NAME="Silent build failure"                       \
TEST_EXPECTED_EXIT=1                                   \
TEST_EXPECTED_OUTPUT_PATTERN="❌ Docker build failed!" \
TEST_EXPECTED_CALLS="build -t myimage:latest ."        \
TEST_DOCKER_SHOULD_FAIL=true                           \
run_test -t myimage:latest .

# Test 4: Normal build with multiple arguments
SILENCE_BUILD=false
DRYRUN=false
VERBOSE=false
TEST_NAME="Normal build with multiple args"                            \
TEST_EXPECTED_EXIT=0                                                   \
TEST_EXPECTED_OUTPUT_PATTERN=""                                        \
TEST_EXPECTED_CALLS="build -f Dockerfile -t myimage:v1.0 --no-cache ." \
run_test -f Dockerfile -t myimage:v1.0 --no-cache .

# Test 5: Silent build with build args
SILENCE_BUILD=true
DRYRUN=false
VERBOSE=false
TEST_NAME="Silent build with build args"                         \
TEST_EXPECTED_EXIT=0                                             \
TEST_EXPECTED_OUTPUT_PATTERN=""                                  \
TEST_EXPECTED_CALLS="build --build-arg VERSION=1.0 -t myimage ." \
run_test --build-arg VERSION=1.0 -t myimage .

# Test 6: Normal build failure (SILENCE_BUILD=false, build fails)
SILENCE_BUILD=false
DRYRUN=false
VERBOSE=false
TEST_NAME="Normal build failure"         \
TEST_EXPECTED_EXIT=1                     \
TEST_EXPECTED_OUTPUT_PATTERN=""          \
TEST_EXPECTED_CALLS="build -t myimage ." \
TEST_DOCKER_SHOULD_FAIL=true             \
run_test -t myimage .

# Test 7: Silent build with verbose (verbose doesn't affect DockerBuild directly)
SILENCE_BUILD=true
DRYRUN=false
VERBOSE=true
TEST_NAME="Silent build with verbose flag" \
TEST_EXPECTED_EXIT=0                       \
TEST_EXPECTED_OUTPUT_PATTERN=""            \
TEST_EXPECTED_CALLS="build -t myimage ."   \
run_test -t myimage .

# Test 8: Normal build with dryrun (dryrun handled by Docker function)
SILENCE_BUILD=false
DRYRUN=true
VERBOSE=false
TEST_NAME="Normal build with dryrun"        \
TEST_EXPECTED_EXIT=0                        \
TEST_EXPECTED_OUTPUT_PATTERN="docker build" \
TEST_EXPECTED_CALLS=""                      \
run_test -t myimage .

# Test 9: Silent build shows error output on failure
SILENCE_BUILD=true
DRYRUN=false
VERBOSE=false
TEST_NAME="Silent build shows error output"           \
TEST_EXPECTED_EXIT=1                                  \
TEST_EXPECTED_OUTPUT_PATTERN="---- Build output ----" \
TEST_EXPECTED_CALLS="build -t myimage ."              \
TEST_DOCKER_SHOULD_FAIL=true                          \
run_test -t myimage .

# Test 10: Empty arguments
SILENCE_BUILD=false
DRYRUN=false
VERBOSE=false
TEST_NAME="Build with no arguments" \
TEST_EXPECTED_EXIT=0                \
TEST_EXPECTED_OUTPUT_PATTERN=""     \
TEST_EXPECTED_CALLS="build"         \
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
