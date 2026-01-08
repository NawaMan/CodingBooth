#!/bin/bash
set -euo pipefail

# Source workspace to get the parse_args_file function
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

# Test helper function for successful cases
run_test() {
  local test_name="$TEST_NAME"
  local expected="$TEST_EXPECTED"
  local file_arg="$TEST_FILE"
  local actual
  
  test_count=$((test_count + 1))
  
  # Call parse_args_file and capture output
  actual=$(parse_args_file "$file_arg" 2>/dev/null || true)
  
  script_relative_path() {
    local script_abs="${1:-$0}"                # absolute path of the script
    local root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

    # Make sure both paths are absolute (realpath handles symlinks too)
    script_abs=$(realpath "$script_abs")
    root=$(realpath "$root")

    # Strip "<root>/tests/" from the front
    echo "${script_abs#${root}/tests/}"
  }

  local script_title=$(script_relative_path "$0")

  if diff -u <(echo "$expected") <(echo "$actual") >/dev/null 2>&1; then
    echo "✅ ${script_title}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${script_title}: Test $test_count: $test_name"
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


SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function for error cases
run_error_test() {
  local test_name="$TEST_NAME"
  local expected_error="$TEST_EXPECTED_ERROR"
  local file_arg="$TEST_FILE"
  local actual_error
  local exit_code
  
  test_count=$((test_count + 1))
  
  # Call parse_args_file and capture stderr
  actual_error=$(parse_args_file "$file_arg" 2>&1 >/dev/null || true)
  exit_code=$?

  if [[ "$actual_error" == *"$expected_error"* ]]; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    echo "Expected error containing: "
    echo "$expected_error"
    echo "-------------------------------------------------------------------------------"
    echo "Actual error: "
    echo "$actual_error"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: Empty file argument → no-op (return 0, no output)
TEST_NAME="Empty file argument" \
TEST_EXPECTED=""                \
TEST_FILE=""                    \
run_test

# Test 2: File argument is 'none' → no-op (return 0, no output)
TEST_NAME="File argument is 'none'" \
TEST_EXPECTED=""                    \
TEST_FILE="none"                    \
run_test

# Test 3: File doesn't exist → error
NONEXISTENT_FILE="$TEST_DIR/nonexistent.txt"
TEST_NAME="File doesn't exist"      \
TEST_EXPECTED_ERROR="is not a file" \
TEST_FILE="$NONEXISTENT_FILE"       \
run_error_test

# Test 4: Argument is a directory → error
TEST_SUBDIR="$TEST_DIR/subdir"
mkdir -p "$TEST_SUBDIR"
TEST_NAME="Argument is a directory" \
TEST_EXPECTED_ERROR="is not a file" \
TEST_FILE="$TEST_SUBDIR"            \
run_error_test

# Test 5: Empty file → no output
EMPTY_FILE="$TEST_DIR/empty.txt"
touch "$EMPTY_FILE"
TEST_NAME="Empty file"  \
TEST_EXPECTED=""        \
TEST_FILE="$EMPTY_FILE" \
run_test

# Test 6: File with only blank lines → no output
BLANK_FILE="$TEST_DIR/blank.txt"
cat > "$BLANK_FILE" << 'EOF'


  
	
EOF
TEST_NAME="File with only blank lines" \
TEST_EXPECTED=""                       \
TEST_FILE="$BLANK_FILE"                \
run_test

# Test 7: File with only comments → no output
COMMENT_FILE="$TEST_DIR/comments.txt"
cat > "$COMMENT_FILE" << 'EOF'
# This is a comment
  # This is an indented comment
	# This is a tab-indented comment
EOF
TEST_NAME="File with only comments" \
TEST_EXPECTED=""                    \
TEST_FILE="$COMMENT_FILE"           \
run_test

# Test 8: File with simple lines
SIMPLE_FILE="$TEST_DIR/simple.txt"
cat > "$SIMPLE_FILE" << 'EOF'
line1
line2
line3
EOF
EXPECTED=$'line1\nline2\nline3'
TEST_NAME="File with simple lines" \
TEST_EXPECTED="$EXPECTED"          \
TEST_FILE="$SIMPLE_FILE"           \
run_test

# Test 9: File with mixed content (lines, blanks, comments)
MIXED_FILE="$TEST_DIR/mixed.txt"
cat > "$MIXED_FILE" << 'EOF'
arg1
# This is a comment
arg2

arg3
  # Another comment
arg4
EOF
EXPECTED=$'arg1\narg2\narg3\narg4'
TEST_NAME="File with mixed content" \
TEST_EXPECTED="$EXPECTED"           \
TEST_FILE="$MIXED_FILE"             \
run_test

# Test 10: File with CRLF line endings
CRLF_FILE="$TEST_DIR/crlf.txt"
printf 'line1\r\nline2\r\nline3\r\n' > "$CRLF_FILE"
EXPECTED=$'line1\nline2\nline3'
TEST_NAME="File with CRLF line endings" \
TEST_EXPECTED="$EXPECTED"               \
TEST_FILE="$CRLF_FILE"                  \
run_test

# Test 11: File with lines containing spaces
SPACES_FILE="$TEST_DIR/spaces.txt"
cat > "$SPACES_FILE" << 'EOF'
arg with spaces
another arg with spaces
EOF
EXPECTED=$'arg with spaces\nanother arg with spaces'
TEST_NAME="File with lines containing spaces" \
TEST_EXPECTED="$EXPECTED"                     \
TEST_FILE="$SPACES_FILE"                      \
run_test

# Test 12: File with leading/trailing whitespace on lines
WHITESPACE_FILE="$TEST_DIR/whitespace.txt"
cat > "$WHITESPACE_FILE" << 'EOF'
  leading spaces
trailing spaces  
	leading tab
trailing tab	
EOF
EXPECTED=$'  leading spaces\ntrailing spaces  \n\tleading tab\ntrailing tab\t'
TEST_NAME="File preserves leading/trailing whitespace" \
TEST_EXPECTED="$EXPECTED"                              \
TEST_FILE="$WHITESPACE_FILE"                           \
run_test

# Test 13: File with no trailing newline
NO_NEWLINE_FILE="$TEST_DIR/no_newline.txt"
printf 'line1\nline2\nline3' > "$NO_NEWLINE_FILE"
EXPECTED=$'line1\nline2\nline3'
TEST_NAME="File with no trailing newline" \
TEST_EXPECTED="$EXPECTED"                 \
TEST_FILE="$NO_NEWLINE_FILE"              \
run_test

# Test 14: File with special characters
SPECIAL_FILE="$TEST_DIR/special.txt"
cat > "$SPECIAL_FILE" << 'EOF'
--arg=value
-v
--flag
arg-with-dashes
arg_with_underscores
arg.with.dots
EOF
EXPECTED=$'--arg=value\n-v\n--flag\narg-with-dashes\narg_with_underscores\narg.with.dots'
TEST_NAME="File with special characters" \
TEST_EXPECTED="$EXPECTED"                \
TEST_FILE="$SPECIAL_FILE"                \
run_test

# Test 15: File with empty lines between content
EMPTY_LINES_FILE="$TEST_DIR/empty_lines.txt"
cat > "$EMPTY_LINES_FILE" << 'EOF'
arg1

arg2


arg3
EOF
EXPECTED=$'arg1\narg2\narg3'
TEST_NAME="File with empty lines between content" \
TEST_EXPECTED="$EXPECTED"                         \
TEST_FILE="$EMPTY_LINES_FILE"                     \
run_test

# Test 16: File with comment-like content in middle of line (should be preserved)
INLINE_COMMENT_FILE="$TEST_DIR/inline_comment.txt"
cat > "$INLINE_COMMENT_FILE" << 'EOF'
arg1 # not a comment
arg2#also not a comment
EOF
EXPECTED=$'arg1 # not a comment\narg2#also not a comment'
TEST_NAME="File with # in middle of line" \
TEST_EXPECTED="$EXPECTED"                 \
TEST_FILE="$INLINE_COMMENT_FILE"          \
run_test

# Test 17: File with mixed CRLF and LF line endings
MIXED_ENDINGS_FILE="$TEST_DIR/mixed_endings.txt"
printf 'line1\r\nline2\nline3\r\n' > "$MIXED_ENDINGS_FILE"
EXPECTED=$'line1\nline2\nline3'
TEST_NAME="File with mixed CRLF and LF endings" \
TEST_EXPECTED="$EXPECTED"                       \
TEST_FILE="$MIXED_ENDINGS_FILE"                 \
run_test

# Test 18: Complex realistic example
REALISTIC_FILE="$TEST_DIR/realistic.txt"
cat > "$REALISTIC_FILE" << 'EOF'
# Configuration file for workspace
--name=myworkspace
--port=8080

# Docker options
--volume=/data:/data
--env=DEBUG=true

# Additional flags
--detach
--rm
EOF
EXPECTED=$'--name=myworkspace\n--port=8080\n--volume=/data:/data\n--env=DEBUG=true\n--detach\n--rm'
TEST_NAME="Realistic configuration file" \
TEST_EXPECTED="$EXPECTED"                \
TEST_FILE="$REALISTIC_FILE"              \
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
