#!/bin/bash
set -euo pipefail

# Source workspace to get the Docker function
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

# Create mock docker script
cat > "$MOCK_DIR/docker" << 'MOCK_SCRIPT'
#!/bin/bash
# Mock docker - logs calls and returns success
echo "$@" >> "$DOCKER_CALLS_FILE"
exit ${DOCKER_EXIT_CODE:-0}
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

# Variable to control exit code
export DOCKER_EXIT_CODE=0

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  local expected_output="$TEST_EXPECTED_OUTPUT"
  local expected_calls="$TEST_EXPECTED_CALLS"
  
  test_count=$((test_count + 1))
  
  # Reset docker calls file
  > "$DOCKER_CALLS_FILE"
  export DOCKER_EXIT_CODE=0
  
  # Capture output to file to preserve trailing newlines
  local output_file=$(mktemp)
  Docker "$@" >"$output_file" 2>&1 || true
  
  # Read file preserving trailing newlines
  local actual_output
  actual_output=$(<"$output_file")
  # Add back one trailing newline that command substitution strips
  if [[ -s "$output_file" ]]; then
    actual_output="${actual_output}"$'\n'
  fi
  rm -f "$output_file"
  
  # Read calls from file
  local actual_calls
  if [[ -s "$DOCKER_CALLS_FILE" ]]; then
    actual_calls=$(cat "$DOCKER_CALLS_FILE")
  else
    actual_calls=""
  fi

  if diff -u <(printf '%s' "$expected_output") <(printf '%s' "$actual_output") >/dev/null 2>&1 && \
     diff -u <(printf '%s' "$expected_calls") <(printf '%s' "$actual_calls") >/dev/null 2>&1; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "Expected output: "
    printf '%s' "$expected_output" | cat -A
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "Actual output: "
    printf '%s' "$actual_output" | cat -A
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "Expected calls: "
    printf '%s' "$expected_calls"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "Actual calls: "
    printf '%s' "$actual_calls"
    echo ""
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: Simple docker command with DRYRUN=false, VERBOSE=false
DRYRUN=false
VERBOSE=false
TEST_NAME="Simple command, no verbose, no dryrun" \
TEST_EXPECTED_OUTPUT=""                           \
TEST_EXPECTED_CALLS="run --name test"             \
run_test run --name test

# Test 2: Docker command with VERBOSE=true
DRYRUN=false
VERBOSE=true
TEST_NAME="Command with verbose"                  \
TEST_EXPECTED_OUTPUT=$'docker run --name test \n' \
TEST_EXPECTED_CALLS="run --name test"             \
run_test run --name test

# Test 3: Docker command with DRYRUN=true (should not execute)
DRYRUN=true
VERBOSE=false
TEST_NAME="Command with dryrun (no execution)"    \
TEST_EXPECTED_OUTPUT=$'docker run --name test \n' \
TEST_EXPECTED_CALLS=""                            \
run_test run --name test

# Test 4: Docker command with both VERBOSE and DRYRUN
DRYRUN=true
VERBOSE=true
TEST_NAME="Command with verbose and dryrun"       \
TEST_EXPECTED_OUTPUT=$'docker run --name test \n' \
TEST_EXPECTED_CALLS=""                            \
run_test run --name test

# Test 5: Docker command with arguments containing spaces
DRYRUN=false
VERBOSE=false
TEST_NAME="Command with spaces in args"                                  \
TEST_EXPECTED_OUTPUT=""                                                  \
TEST_EXPECTED_CALLS="run --name my container -v /path/with spaces:/data" \
run_test run --name "my container" -v "/path/with spaces:/data"

# Test 6: Docker command with special characters
DRYRUN=false
VERBOSE=true
TEST_NAME="Command with special characters"                           \
TEST_EXPECTED_OUTPUT=$'docker run --env \'KEY=value\' --name test \n' \
TEST_EXPECTED_CALLS="run --env KEY=value --name test"                 \
run_test run --env KEY=value --name test

# Test 7: Docker build command
DRYRUN=false
VERBOSE=false
TEST_NAME="Docker build command"                \
TEST_EXPECTED_OUTPUT=""                         \
TEST_EXPECTED_CALLS="build -t myimage:latest ." \
run_test build -t myimage:latest .

# Test 8: Docker pull command with verbose
DRYRUN=false
VERBOSE=true
TEST_NAME="Docker pull with verbose"                 \
TEST_EXPECTED_OUTPUT=$'docker pull ubuntu:latest \n' \
TEST_EXPECTED_CALLS="pull ubuntu:latest"             \
run_test pull ubuntu:latest

# Test 9: Multiple arguments
DRYRUN=false
VERBOSE=false
TEST_NAME="Multiple complex arguments"                                               \
TEST_EXPECTED_OUTPUT=""                                                              \
TEST_EXPECTED_CALLS="run -it --rm --name test -v /data:/data -p 8080:80 ubuntu bash" \
run_test run -it --rm --name test -v /data:/data -p 8080:80 ubuntu bash

# Test 10: Empty subcmd (edge case)
DRYRUN=false
VERBOSE=false
TEST_NAME="Empty subcommand" \
TEST_EXPECTED_OUTPUT=""      \
TEST_EXPECTED_CALLS=""       \
run_test ""

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
