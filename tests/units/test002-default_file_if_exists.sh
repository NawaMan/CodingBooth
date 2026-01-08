#!/bin/bash
set -euo pipefail

# Source workspace to get the default_file_if_exists function
# Set SKIP_MAIN to prevent the main script from executing
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

# Create a temporary directory for test files
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create test files
EXISTING_FILE1="$TEST_DIR/existing1.txt"
EXISTING_FILE2="$TEST_DIR/existing2.txt"
NONEXISTENT_FILE="$TEST_DIR/nonexistent.txt"

echo "content1" > "$EXISTING_FILE1"
echo "content2" > "$EXISTING_FILE2"

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  local expected="$TEST_EXPECTED"
  local actual
  
  test_count=$((test_count + 1))
  
  # Call default_file_if_exists with remaining arguments
  actual=$(default_file_if_exists "$@")

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

# Test 1: Empty current, candidate exists → pick candidate
TEST_NAME="Empty current, candidate exists" \
TEST_EXPECTED="$EXISTING_FILE1"             \
run_test "" "$EXISTING_FILE1"

# Test 2: Empty current, candidate doesn't exist → keep current (empty)
TEST_NAME="Empty current, candidate doesn't exist" \
TEST_EXPECTED=""                                   \
run_test "" "$NONEXISTENT_FILE"

# Test 3: Current set, candidate exists → keep current
TEST_NAME="Current set, candidate exists" \
TEST_EXPECTED="$EXISTING_FILE2"           \
run_test "$EXISTING_FILE2" "$EXISTING_FILE1"

# Test 4: Current set, candidate doesn't exist → keep current
TEST_NAME="Current set, candidate doesn't exist" \
TEST_EXPECTED="$EXISTING_FILE1"                  \
run_test "$EXISTING_FILE1" "$NONEXISTENT_FILE"

# Test 5: Current equals "not_used" token, candidate exists → pick candidate
TEST_NAME="Current is 'none', candidate exists" \
TEST_EXPECTED="$EXISTING_FILE1"                 \
run_test "none" "$EXISTING_FILE1" "none"

# Test 6: Current equals custom "not_used" token, candidate exists → pick candidate
TEST_NAME="Current is custom token, candidate exists" \
TEST_EXPECTED="$EXISTING_FILE1"                       \
run_test "skip" "$EXISTING_FILE1" "skip"

# Test 7: Current equals "not_used" token, candidate doesn't exist → keep current
TEST_NAME="Current is 'none', candidate doesn't exist" \
TEST_EXPECTED="none"                                   \
run_test "none" "$NONEXISTENT_FILE" "none"

# Test 8: Current is different from "not_used" token → keep current
TEST_NAME="Current != not_used token" \
TEST_EXPECTED="$EXISTING_FILE2"       \
run_test "$EXISTING_FILE2" "$EXISTING_FILE1" "different"

# Test 9: All empty arguments → return empty
TEST_NAME="All empty arguments" \
TEST_EXPECTED=""                \
run_test "" ""

# Test 10: Only current provided → keep current
TEST_NAME="Only current provided" \
TEST_EXPECTED="$EXISTING_FILE1"   \
run_test "$EXISTING_FILE1"

# Test 11: Current is nonexistent file, candidate exists → keep current (nonexistent)
TEST_NAME="Current nonexistent, candidate exists" \
TEST_EXPECTED="$NONEXISTENT_FILE"                 \
run_test "$NONEXISTENT_FILE" "$EXISTING_FILE1"

# Test 12: Empty current, empty candidate → keep current (empty)
TEST_NAME="Empty current, empty candidate" \
TEST_EXPECTED=""                           \
run_test "" ""

# Test 13: Current is 'none', candidate is empty → keep current
TEST_NAME="Current is 'none', candidate empty" \
TEST_EXPECTED="none"                           \
run_test "none" "" "none"

# Test 14: Current is 'none', candidate exists, no not_used param → keep current
TEST_NAME="Current is 'none', no not_used param" \
TEST_EXPECTED="none"                             \
run_test "none" "$EXISTING_FILE1"

# Test 15: Empty current, candidate is directory → keep current (directories don't match -f)
EXISTING_DIR="$TEST_DIR/subdir"
mkdir -p "$EXISTING_DIR"
TEST_NAME="Empty current, candidate is directory" \
TEST_EXPECTED=""                                  \
run_test "" "$EXISTING_DIR"

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
