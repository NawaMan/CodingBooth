#!/bin/bash
set -euo pipefail

# Source workspace to get the PortDetermination function
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
  
  # Reset global variables
  WORKSPACE_PORT="${TEST_WORKSPACE_PORT}"
  VERBOSE="${TEST_VERBOSE:-false}"
  CMDS=()
  if [[ -n "${TEST_CMDS:-}" ]]; then
    eval "CMDS=(${TEST_CMDS})"
  fi
  HOST_PORT=""
  PORT_GENERATED=false
  
  # Call PortDetermination
  PortDetermination >/dev/null 2>&1
  
  # Check results
  local all_match=true
  local mismatches=""
  
  for var_check in "${TEST_EXPECTED[@]}"; do
    local var_name="${var_check%%=*}"
    local expected_value="${var_check#*=}"
    
    local actual_value=""
    case "$var_name" in
      HOST_PORT)
        actual_value="${HOST_PORT}"
        ;;
      PORT_GENERATED)
        actual_value="${PORT_GENERATED}"
        ;;
      HOST_PORT_RANGE)
        # Check if HOST_PORT is within expected range
        local min_port="${expected_value%-*}"
        local max_port="${expected_value#*-}"
        if (( HOST_PORT >= min_port && HOST_PORT <= max_port )); then
          continue
        else
          all_match=false
          mismatches+="  HOST_PORT: expected range $expected_value, actual=$HOST_PORT"$'\n'
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

# Test 1: Specific port number
TEST_NAME="Specific port 8080"
TEST_WORKSPACE_PORT="8080"
TEST_EXPECTED=(
  "HOST_PORT=8080"
  "PORT_GENERATED=false"
)
run_test

# Test 2: Port 10000
TEST_NAME="Port 10000"
TEST_WORKSPACE_PORT="10000"
TEST_EXPECTED=(
  "HOST_PORT=10000"
  "PORT_GENERATED=false"
)
run_test

# Test 3: NEXT port (finds first free port)
TEST_NAME="NEXT port"
TEST_WORKSPACE_PORT="NEXT"
TEST_EXPECTED=(
  "HOST_PORT_RANGE=10000-65535"
  "PORT_GENERATED=true"
)
run_test

# Test 4: next (lowercase)
TEST_NAME="next (lowercase)"
TEST_WORKSPACE_PORT="next"
TEST_EXPECTED=(
  "HOST_PORT_RANGE=10000-65535"
  "PORT_GENERATED=true"
)
run_test

# Test 5: RANDOM port
TEST_NAME="RANDOM port"
TEST_WORKSPACE_PORT="RANDOM"
TEST_EXPECTED=(
  "HOST_PORT_RANGE=10001-65535"
  "PORT_GENERATED=true"
)
run_test

# Test 6: random (lowercase)
TEST_NAME="random (lowercase)"
TEST_WORKSPACE_PORT="random"
TEST_EXPECTED=(
  "HOST_PORT_RANGE=10001-65535"
  "PORT_GENERATED=true"
)
run_test

# Test 7: Low port number
TEST_NAME="Low port 80"
TEST_WORKSPACE_PORT="80"
TEST_EXPECTED=(
  "HOST_PORT=80"
  "PORT_GENERATED=false"
)
run_test

# Test 8: High port number
TEST_NAME="High port 65535"
TEST_WORKSPACE_PORT="65535"
TEST_EXPECTED=(
  "HOST_PORT=65535"
  "PORT_GENERATED=false"
)
run_test

# Test 9: Port 1 (minimum)
TEST_NAME="Port 1 (minimum)"
TEST_WORKSPACE_PORT="1"
TEST_EXPECTED=(
  "HOST_PORT=1"
  "PORT_GENERATED=false"
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
echo "NOTE: Error cases (invalid ports, out of range) are not tested because"
echo "      the function calls 'exit 1' which would terminate this script."
echo "==============================================================================="

if [ $fail_count -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed!"
  exit 1
fi
