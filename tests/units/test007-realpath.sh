#!/bin/bash
set -euo pipefail

# Source workspace to get the realpath function
# Set SKIP_MAIN to prevent the main script from executing
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

# Create a temporary directory for test files and directories
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  local expected="$TEST_EXPECTED"
  local input="$TEST_INPUT"
  local actual
  
  test_count=$((test_count + 1))
  
  # Call realpath
  actual=$(realpath "$input")

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

# Setup test directory structure
mkdir -p "$TEST_DIR/dir1/subdir"
mkdir -p "$TEST_DIR/dir2"
touch "$TEST_DIR/file1.txt"
touch "$TEST_DIR/dir1/file2.txt"
touch "$TEST_DIR/dir1/subdir/file3.txt"

# Create symbolic links
ln -s "$TEST_DIR/dir1" "$TEST_DIR/link_to_dir1"
ln -s "$TEST_DIR/file1.txt" "$TEST_DIR/link_to_file1"
ln -s "$TEST_DIR/dir1/subdir" "$TEST_DIR/link_to_subdir"
ln -s "file1.txt" "$TEST_DIR/relative_link"


supports_dir_symlinks=true
if [[ "$(realpath "$TEST_DIR/link_to_dir1")" != "$(realpath "$TEST_DIR/dir1")" ]]; then
  supports_dir_symlinks=false
fi
cd "$PWD"


# Test 1: Absolute path to existing directory
TEST_NAME="Absolute path to existing directory" \
TEST_EXPECTED="$TEST_DIR/dir1"                  \
TEST_INPUT="$TEST_DIR/dir1"                     \
run_test

# Test 2: Absolute path to existing file
TEST_NAME="Absolute path to existing file" \
TEST_EXPECTED="$TEST_DIR/file1.txt"        \
TEST_INPUT="$TEST_DIR/file1.txt"           \
run_test

# Test 3: Relative path to current directory
ORIGINAL_PWD="$PWD"
cd "$TEST_DIR"
TEST_NAME="Relative path - current directory" \
TEST_EXPECTED="$TEST_DIR"                     \
TEST_INPUT="."                                \
run_test
cd "$ORIGINAL_PWD"

# Test 4: Relative path to parent directory
cd "$TEST_DIR/dir1"
TEST_NAME="Relative path - parent directory" \
TEST_EXPECTED="$TEST_DIR"                    \
TEST_INPUT=".."                              \
run_test
cd "$ORIGINAL_PWD"

# Test 5: Relative path to subdirectory
cd "$TEST_DIR"
TEST_NAME="Relative path to subdirectory" \
TEST_EXPECTED="$TEST_DIR/dir1"            \
TEST_INPUT="dir1"                         \
run_test
cd "$ORIGINAL_PWD"

# Test 6: Relative path to file
cd "$TEST_DIR"
TEST_NAME="Relative path to file"   \
TEST_EXPECTED="$TEST_DIR/file1.txt" \
TEST_INPUT="file1.txt"              \
run_test
cd "$ORIGINAL_PWD"

# Test 7: Relative path with ./
cd "$TEST_DIR"
TEST_NAME="Relative path with ./" \
TEST_EXPECTED="$TEST_DIR/dir1"    \
TEST_INPUT="./dir1"               \
run_test
cd "$ORIGINAL_PWD"

# Test 8: Relative path with ../
cd "$TEST_DIR/dir1"
TEST_NAME="Relative path with ../" \
TEST_EXPECTED="$TEST_DIR/dir2"     \
TEST_INPUT="../dir2"               \
run_test
cd "$ORIGINAL_PWD"

# Test 9: Nested relative path
cd "$TEST_DIR"
TEST_NAME="Nested relative path"                \
TEST_EXPECTED="$TEST_DIR/dir1/subdir/file3.txt" \
TEST_INPUT="dir1/subdir/file3.txt"              \
run_test
cd "$ORIGINAL_PWD"

# Test 10: Symbolic link to directory (should resolve)
if $supports_dir_symlinks; then
  TEST_NAME="Symlink to directory"    \
  TEST_EXPECTED="$TEST_DIR/dir1"      \
  TEST_INPUT="$TEST_DIR/link_to_dir1" \
  run_test
else
  echo "⚠️  ${SCRIPT_TITLE}: Skipping test 10 (directory symlinks not supported)"
fi

# Test 11: Symbolic link to file (parent dir resolved, filename preserved)
TEST_NAME="Symlink to file"             \
TEST_EXPECTED="$TEST_DIR/link_to_file1" \
TEST_INPUT="$TEST_DIR/link_to_file1"    \
run_test

# Test 12: Path through symbolic link
if $supports_dir_symlinks; then
  TEST_NAME="Path through symlink"              \
  TEST_EXPECTED="$TEST_DIR/dir1/file2.txt"      \
  TEST_INPUT="$TEST_DIR/link_to_dir1/file2.txt" \
  run_test
else
  echo "⚠️  ${SCRIPT_TITLE}: Skipping test 12 (directory symlinks not supported)"
fi

# Test 13: Relative symbolic link
cd "$TEST_DIR"
TEST_NAME="Relative symlink"            \
TEST_EXPECTED="$TEST_DIR/relative_link" \
TEST_INPUT="relative_link"              \
run_test
cd "$ORIGINAL_PWD"

# Test 14: Non-existent directory (returns as-is)
TEST_NAME="Non-existent directory"    \
TEST_EXPECTED="$TEST_DIR/nonexistent" \
TEST_INPUT="$TEST_DIR/nonexistent"    \
run_test

# Test 15: Non-existent file in existing directory
TEST_NAME="Non-existent file in existing dir"  \
TEST_EXPECTED="$TEST_DIR/dir1/nonexistent.txt" \
TEST_INPUT="$TEST_DIR/dir1/nonexistent.txt"    \
run_test

# Test 16: Non-existent file in non-existent directory (returns as-is)
TEST_NAME="Non-existent file in non-existent dir" \
TEST_EXPECTED="$TEST_DIR/nonexistent/file.txt"    \
TEST_INPUT="$TEST_DIR/nonexistent/file.txt"       \
run_test

# Test 17: Path with trailing slash (directory)
TEST_NAME="Directory with trailing slash" \
TEST_EXPECTED="$TEST_DIR/dir1"            \
TEST_INPUT="$TEST_DIR/dir1/"              \
run_test

# Test 18: Complex path with multiple ../
cd "$TEST_DIR/dir1/subdir"
TEST_NAME="Complex path with multiple ../" \
TEST_EXPECTED="$TEST_DIR/dir2"             \
TEST_INPUT="../../dir2"                    \
run_test
cd "$ORIGINAL_PWD"

# Test 19: Path with redundant /./
cd "$TEST_DIR"
TEST_NAME="Path with redundant /./"      \
TEST_EXPECTED="$TEST_DIR/dir1/file2.txt" \
TEST_INPUT="./dir1/./file2.txt"          \
run_test
cd "$ORIGINAL_PWD"

# Test 20: Absolute path (already absolute)
TEST_NAME="Already absolute path"     \
TEST_EXPECTED="$TEST_DIR/dir1/subdir" \
TEST_INPUT="$TEST_DIR/dir1/subdir"    \
run_test

# Test 21: Root directory
TEST_NAME="Root directory" \
TEST_EXPECTED="/"          \
TEST_INPUT="/"             \
run_test

# Test 22: Path starting with ~/ (if HOME is set)
if [[ -n "${HOME:-}" ]]; then
  cd "$HOME"
  EXPECTED="$HOME"
  TEST_NAME="Home directory with ~"
TEST_EXPECTED="$EXPECTED" \
TEST_INPUT="."            \
run_test
  cd "$ORIGINAL_PWD"
fi

# Test 23: Empty directory name (edge case)
cd "$TEST_DIR"
TEST_NAME="Current directory from within" \
TEST_EXPECTED="$TEST_DIR"                 \
TEST_INPUT="."                            \
run_test
cd "$ORIGINAL_PWD"

# Test 24: File in deeply nested directory
TEST_NAME="Deeply nested file"                  \
TEST_EXPECTED="$TEST_DIR/dir1/subdir/file3.txt" \
TEST_INPUT="$TEST_DIR/dir1/subdir/file3.txt"    \
run_test

# Test 25: Symlink to nested directory (only if directory symlinks are supported)
if $supports_dir_symlinks; then
  TEST_NAME="Symlink to nested directory" \
  TEST_EXPECTED="$TEST_DIR/dir1/subdir"   \
  TEST_INPUT="$TEST_DIR/link_to_subdir"   \
  run_test
else
  echo "⚠️  ${SCRIPT_TITLE}: Skipping test 25 (directory symlinks not supported)"
fi

# Test 26: Path through symlink to nested location (only if directory symlinks are supported)
if $supports_dir_symlinks; then
  TEST_NAME="Path through symlink to nested"      \
  TEST_EXPECTED="$TEST_DIR/dir1/subdir/file3.txt" \
  TEST_INPUT="$TEST_DIR/link_to_subdir/file3.txt" \
  run_test
else
  echo "⚠️  ${SCRIPT_TITLE}: Skipping test 26 (directory symlinks not supported)"
fi

# Test 27: Relative path from different directory
cd /tmp
EXPECTED="$TEST_DIR/dir1"
TEST_NAME="Absolute path from /tmp" \
TEST_EXPECTED="$EXPECTED"           \
TEST_INPUT="$TEST_DIR/dir1"         \
run_test
cd "$ORIGINAL_PWD"

# Test 28: Path with spaces in directory name
SPACE_DIR="$TEST_DIR/dir with spaces"
mkdir -p "$SPACE_DIR"
TEST_NAME="Directory with spaces" \
TEST_EXPECTED="$SPACE_DIR"        \
TEST_INPUT="$SPACE_DIR"           \
run_test

# Test 29: Path with spaces in filename
SPACE_FILE="$TEST_DIR/file with spaces.txt"
touch "$SPACE_FILE"
TEST_NAME="File with spaces" \
TEST_EXPECTED="$SPACE_FILE"  \
TEST_INPUT="$SPACE_FILE"     \
run_test

# Test 30: Single dot (current directory)
cd "$TEST_DIR/dir1"
TEST_NAME="Single dot"         \
TEST_EXPECTED="$TEST_DIR/dir1" \
TEST_INPUT="."                 \
run_test
cd "$ORIGINAL_PWD"

# Test 31: Double dot (parent directory)
cd "$TEST_DIR/dir1"
TEST_NAME="Double dot"    \
TEST_EXPECTED="$TEST_DIR" \
TEST_INPUT=".."           \
run_test
cd "$ORIGINAL_PWD"

# Test 32: File basename only (in current directory)
cd "$TEST_DIR"
TEST_NAME="File basename only"      \
TEST_EXPECTED="$TEST_DIR/file1.txt" \
TEST_INPUT="file1.txt"              \
run_test
cd "$ORIGINAL_PWD"

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
