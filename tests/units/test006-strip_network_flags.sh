#!/bin/bash
set -euo pipefail

# Source workspace to get the strip_network_flags function
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
  local expected="$TEST_EXPECTED"
  local actual
  
  test_count=$((test_count + 1))
  
  # Call strip_network_flags with remaining arguments
  # Capture output line by line
  actual=$(strip_network_flags "$@")

  if diff -u <(echo "$expected") <(echo "$actual") >/dev/null 2>&1; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "Expected: "
    echo "$expected"
    echo "-------------------------------------------------------------------------------"
    echo "Actual: "
    echo "$actual"
    echo "-------------------------------------------------------------------------------"
    diff -u <(echo "$expected") <(echo "$actual") || true
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: No arguments
TEST_NAME="No arguments" \
TEST_EXPECTED=""         \
run_test

# Test 2: Arguments without network flags
EXPECTED=$'--name=myapp\n--port=8080\n--detach'
TEST_NAME="No network flags" \
TEST_EXPECTED="$EXPECTED"    \
run_test "--name=myapp" "--port=8080" "--detach"

# Test 3: --network with value (two tokens)
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--network with separate value" \
TEST_EXPECTED="$EXPECTED"                 \
run_test "--name=myapp" "--network" "bridge" "--detach"

# Test 4: --network=value (single token)
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--network=value (single token)" \
TEST_EXPECTED="$EXPECTED"                  \
run_test "--name=myapp" "--network=bridge" "--detach"

# Test 5: --net with value (two tokens)
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--net with separate value" \
TEST_EXPECTED="$EXPECTED"             \
run_test "--name=myapp" "--net" "host" "--detach"

# Test 6: --net=value (single token)
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--net=value (single token)" \
TEST_EXPECTED="$EXPECTED"              \
run_test "--name=myapp" "--net=host" "--detach"

# Test 7: Multiple --network flags
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="Multiple --network flags" \
TEST_EXPECTED="$EXPECTED"            \
run_test "--name=myapp" "--network" "bridge" "--network" "host" "--detach"

# Test 8: Multiple --net flags
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="Multiple --net flags" \
TEST_EXPECTED="$EXPECTED"        \
run_test "--name=myapp" "--net" "bridge" "--net" "host" "--detach"

# Test 9: Mix of --network and --net
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="Mix of --network and --net" \
TEST_EXPECTED="$EXPECTED"              \
run_test "--name=myapp" "--network" "bridge" "--net" "host" "--detach"

# Test 10: Mix of formats (--network value and --net=value)
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="Mix of formats" \
TEST_EXPECTED="$EXPECTED"  \
run_test "--name=myapp" "--network" "bridge" "--net=host" "--detach"

# Test 11: --network at the beginning
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--network at beginning" \
TEST_EXPECTED="$EXPECTED"          \
run_test "--network" "bridge" "--name=myapp" "--detach"

# Test 12: --network at the end
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--network at end" \
TEST_EXPECTED="$EXPECTED"    \
run_test "--name=myapp" "--detach" "--network" "bridge"

# Test 13: Only --network flag
TEST_NAME="Only --network flag" \
TEST_EXPECTED=""                \
run_test "--network" "bridge"

# Test 14: Only --network=value flag
TEST_NAME="Only --network=value flag" \
TEST_EXPECTED=""                      \
run_test "--network=bridge"

# Test 15: --network with complex value
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--network with complex value" \
TEST_EXPECTED="$EXPECTED"                \
run_test "--name=myapp" "--network" "container:mycontainer" "--detach"

# Test 16: --network=value with complex value
EXPECTED=$'--name=myapp\n--detach'
TEST_NAME="--network=value with complex value" \
TEST_EXPECTED="$EXPECTED"                      \
run_test "--name=myapp" "--network=container:mycontainer" "--detach"

# Test 17: Preserve arguments that contain 'network' but aren't the flag
EXPECTED=$'--name=network-app\n--env=NETWORK_MODE=bridge\n--detach'
TEST_NAME="Preserve args containing 'network'" \
TEST_EXPECTED="$EXPECTED"                      \
run_test "--name=network-app" "--env=NETWORK_MODE=bridge" "--detach"

# Test 18: --network-mode should NOT be stripped (different flag)
EXPECTED=$'--network-mode=bridge\n--name=myapp'
TEST_NAME="--network-mode not stripped" \
TEST_EXPECTED="$EXPECTED"               \
run_test "--network-mode=bridge" "--name=myapp"

# Test 19: Multiple consecutive --network flags
EXPECTED=$'--name=myapp'
TEST_NAME="Multiple consecutive --network flags" \
TEST_EXPECTED="$EXPECTED"                        \
run_test "--network" "bridge" "--network" "host" "--name=myapp"

# Test 20: --network followed by another flag (edge case - next arg is consumed)
EXPECTED=""
TEST_NAME="--network followed by flag-like value" \
TEST_EXPECTED="$EXPECTED"                         \
run_test "--network" "--name=myapp"

# Test 21: Empty string arguments preserved (except network flags)
EXPECTED=$'--name=myapp\n\n--detach'
TEST_NAME="Empty string arguments preserved" \
TEST_EXPECTED="$EXPECTED"                    \
run_test "--name=myapp" "" "--detach"

# Test 22: Arguments with spaces
EXPECTED=$'--name=my app\n--env=KEY=value with spaces\n--detach'
TEST_NAME="Arguments with spaces" \
TEST_EXPECTED="$EXPECTED"         \
run_test "--name=my app" "--env=KEY=value with spaces" "--detach"

# Test 23: --network with empty value
EXPECTED=$'--name=myapp'
TEST_NAME="--network with empty value" \
TEST_EXPECTED="$EXPECTED"              \
run_test "--network" "" "--name=myapp"

# Test 24: --network= (equals but no value)
TEST_NAME="--network= (empty after equals)" \
TEST_EXPECTED=""                            \
run_test "--network="

# Test 25: --net= (equals but no value)
TEST_NAME="--net= (empty after equals)" \
TEST_EXPECTED=""                        \
run_test "--net="

# Test 26: Complex realistic example
EXPECTED=$'--name=myapp\n--port=8080:80\n--volume=/data:/data\n--env=DEBUG=true\n--detach\n--rm'
TEST_NAME="Complex realistic example" \
TEST_EXPECTED="$EXPECTED"             \
run_test                      \
  "--name=myapp"              \
  "--network" "bridge"        \
  "--port=8080:80"            \
  "--volume=/data:/data"      \
  "--net=host"                \
  "--env=DEBUG=true"          \
  "--detach"                  \
  "--network=container:other" \
  "--rm"

# Test 27: Single character after --network
EXPECTED=$'--name=myapp'
TEST_NAME="Single char after --network" \
TEST_EXPECTED="$EXPECTED"               \
run_test "--network" "a" "--name=myapp"

# Test 28: Numeric value after --network
EXPECTED=$'--name=myapp'
TEST_NAME="Numeric value after --network" \
TEST_EXPECTED="$EXPECTED"                 \
run_test "--network" "123" "--name=myapp"

# Test 29: Special characters in network value
EXPECTED=$'--name=myapp'
TEST_NAME="Special chars in network value" \
TEST_EXPECTED="$EXPECTED"                  \
run_test "--network" "my-custom_network.123" "--name=myapp"

# Test 30: --network with path-like value
EXPECTED=$'--name=myapp'
TEST_NAME="--network with path-like value" \
TEST_EXPECTED="$EXPECTED"                  \
run_test "--network" "/var/run/network" "--name=myapp"

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
