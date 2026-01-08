#!/bin/bash
set -euo pipefail

# Source workspace to get the project_name function
# Set SKIP_MAIN to prevent the main script from executing
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

# Create a temporary directory for test directories
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function
run_test() {
  local test_name="$TEST_NAME"
  local expected="$TEST_EXPECTED"
  local input="${TEST_INPUT:-}"
  local actual
  
  test_count=$((test_count + 1))
  
  # Call project_name with the input (or no argument if empty)
  if [[ -z "$input" ]]; then
    actual=$(project_name 2>/dev/null)
  else
    actual=$(project_name "$input" 2>/dev/null)
  fi

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

supports_dir_symlinks=true
if [[ "$(realpath "$TEST_DIR/link_to_dir1")" != "$(realpath "$TEST_DIR/dir1")" ]]; then
  supports_dir_symlinks=false
fi
cd "$PWD"

# Test 1: No argument → use current directory (PWD)
# Save current directory and change to a known location
ORIGINAL_PWD="$PWD"
TEST_PROJECT_DIR="$TEST_DIR/MyTestProject"
mkdir -p "$TEST_PROJECT_DIR"
cd "$TEST_PROJECT_DIR"
TEST_NAME="No argument uses PWD" \
TEST_EXPECTED="mytestproject"    \
run_test
cd "$ORIGINAL_PWD"

# Test 2: Simple lowercase directory name
SIMPLE_DIR="$TEST_DIR/simple"
mkdir -p "$SIMPLE_DIR"
TEST_NAME="Simple lowercase name" \
TEST_EXPECTED="simple"            \
TEST_INPUT="$SIMPLE_DIR"          \
run_test

# Test 3: Uppercase letters → converted to lowercase
UPPER_DIR="$TEST_DIR/UPPERCASE"
mkdir -p "$UPPER_DIR"
TEST_NAME="Uppercase converted to lowercase" \
TEST_EXPECTED="uppercase"                    \
TEST_INPUT="$UPPER_DIR"                      \
run_test

# Test 4: Mixed case → converted to lowercase
MIXED_DIR="$TEST_DIR/MixedCase"
mkdir -p "$MIXED_DIR"
TEST_NAME="Mixed case converted to lowercase" \
TEST_EXPECTED="mixedcase"                     \
TEST_INPUT="$MIXED_DIR"                       \
run_test

# Test 5: Spaces → converted to dashes
SPACE_DIR="$TEST_DIR/my project name"
mkdir -p "$SPACE_DIR"
TEST_NAME="Spaces converted to dashes" \
TEST_EXPECTED="my-project-name"        \
TEST_INPUT="$SPACE_DIR"                \
run_test

# Test 6: Multiple spaces → each converted to dash (not collapsed)
MULTI_SPACE_DIR="$TEST_DIR/my   project"
mkdir -p "$MULTI_SPACE_DIR"
TEST_NAME="Multiple spaces to multiple dashes" \
TEST_EXPECTED="my---project"                   \
TEST_INPUT="$MULTI_SPACE_DIR"                  \
run_test

# Test 7: Special characters → converted to dashes
SPECIAL_DIR="$TEST_DIR/my@project#name"
mkdir -p "$SPECIAL_DIR"
TEST_NAME="Special characters to dashes" \
TEST_EXPECTED="my-project-name"          \
TEST_INPUT="$SPECIAL_DIR"                \
run_test

# Test 8: Leading dashes → removed
LEADING_DASH_DIR="$TEST_DIR/---project"
mkdir -p "$LEADING_DASH_DIR"
TEST_NAME="Leading dashes removed" \
TEST_EXPECTED="project"            \
TEST_INPUT="$LEADING_DASH_DIR"     \
run_test

# Test 9: Trailing dashes → removed
TRAILING_DASH_DIR="$TEST_DIR/project---"
mkdir -p "$TRAILING_DASH_DIR"
TEST_NAME="Trailing dashes removed" \
TEST_EXPECTED="project"             \
TEST_INPUT="$TRAILING_DASH_DIR"     \
run_test

# Test 10: Allowed characters (lowercase, digits, underscore, dot, dash)
ALLOWED_DIR="$TEST_DIR/my-project_v1.0"
mkdir -p "$ALLOWED_DIR"
TEST_NAME="Allowed characters preserved" \
TEST_EXPECTED="my-project_v1.0"          \
TEST_INPUT="$ALLOWED_DIR"                \
run_test

# Test 11: Consecutive special characters → single dash
CONSECUTIVE_DIR="$TEST_DIR/my@@##project"
mkdir -p "$CONSECUTIVE_DIR"
TEST_NAME="Consecutive special chars to single dash" \
TEST_EXPECTED="my-project"                           \
TEST_INPUT="$CONSECUTIVE_DIR"                        \
run_test

# Test 12: Dots preserved
DOT_DIR="$TEST_DIR/my.project.name"
mkdir -p "$DOT_DIR"
TEST_NAME="Dots preserved"      \
TEST_EXPECTED="my.project.name" \
TEST_INPUT="$DOT_DIR"           \
run_test

# Test 13: Underscores preserved
UNDERSCORE_DIR="$TEST_DIR/my_project_name"
mkdir -p "$UNDERSCORE_DIR"
TEST_NAME="Underscores preserved" \
TEST_EXPECTED="my_project_name"   \
TEST_INPUT="$UNDERSCORE_DIR"      \
run_test

# Test 14: Numbers preserved
NUMBER_DIR="$TEST_DIR/project123"
mkdir -p "$NUMBER_DIR"
TEST_NAME="Numbers preserved" \
TEST_EXPECTED="project123"    \
TEST_INPUT="$NUMBER_DIR"      \
run_test

# Test 15: Complex realistic name
COMPLEX_DIR="$TEST_DIR/My Project (v2.0) - FINAL!"
mkdir -p "$COMPLEX_DIR"
TEST_NAME="Complex realistic name"        \
TEST_EXPECTED="my-project--v2.0----final" \
TEST_INPUT="$COMPLEX_DIR"                 \
run_test

# Test 16: Path with parent directories (should use basename)
NESTED_DIR="$TEST_DIR/parent/child/ProjectName"
mkdir -p "$NESTED_DIR"
TEST_NAME="Nested path uses basename" \
TEST_EXPECTED="projectname"           \
TEST_INPUT="$NESTED_DIR"              \
run_test

# Test 17: Relative path
REL_DIR="$TEST_DIR/relative-test"
mkdir -p "$REL_DIR"
cd "$TEST_DIR"
TEST_NAME="Relative path"     \
TEST_EXPECTED="relative-test" \
TEST_INPUT="./relative-test"  \
run_test
cd "$ORIGINAL_PWD"

# Test 18: Path with trailing slash
TRAILING_SLASH_DIR="$TEST_DIR/trailing"
mkdir -p "$TRAILING_SLASH_DIR"
TEST_NAME="Path with trailing slash" \
TEST_EXPECTED="trailing"             \
TEST_INPUT="$TRAILING_SLASH_DIR/"    \
run_test

# Test 19: All special characters → fallback to "workspace"
# Create a directory with only special characters that all get stripped
ONLY_SPECIAL_DIR="$TEST_DIR/@@@"
mkdir -p "$ONLY_SPECIAL_DIR"
TEST_NAME="All special chars fallback to workspace" \
TEST_EXPECTED="workspace"                           \
TEST_INPUT="$ONLY_SPECIAL_DIR"                      \
run_test

# Test 20: Symbolic link (should resolve to target)
if $supports_dir_symlinks; then
  SYMLINK_TARGET="$TEST_DIR/SymlinkTarget"
  SYMLINK_DIR="$TEST_DIR/symlink"
  mkdir -p "$SYMLINK_TARGET"
  ln -s "$SYMLINK_TARGET" "$SYMLINK_DIR"
  TEST_NAME="Symbolic link resolves to target" \
  TEST_EXPECTED="symlinktarget"                \
  TEST_INPUT="$SYMLINK_DIR"                    \
  run_test
else
  echo "⚠️  ${SCRIPT_TITLE}: Skipping test 20 (directory symlinks not supported)"
fi

# Test 21: Mix of uppercase, spaces, and special chars
KITCHEN_SINK_DIR="$TEST_DIR/My AWESOME Project!!! (2024)"
mkdir -p "$KITCHEN_SINK_DIR"
TEST_NAME="Kitchen sink example"          \
TEST_EXPECTED="my-awesome-project---2024" \
TEST_INPUT="$KITCHEN_SINK_DIR"            \
run_test

# Test 22: Hyphens already present (should be preserved)
HYPHEN_DIR="$TEST_DIR/my-existing-project"
mkdir -p "$HYPHEN_DIR"
TEST_NAME="Existing hyphens preserved" \
TEST_EXPECTED="my-existing-project"    \
TEST_INPUT="$HYPHEN_DIR"               \
run_test

# Test 23: Leading and trailing spaces in directory name
SPACE_TRIM_DIR="$TEST_DIR/  spaced  "
mkdir -p "$SPACE_TRIM_DIR"
TEST_NAME="Leading/trailing spaces handled" \
TEST_EXPECTED="spaced"                      \
TEST_INPUT="$SPACE_TRIM_DIR"                \
run_test

# Test 24: Unicode/non-ASCII characters → preserved (not in regex pattern)
UNICODE_DIR="$TEST_DIR/project-café"
mkdir -p "$UNICODE_DIR"
TEST_NAME="Unicode chars preserved" \
TEST_EXPECTED="project-cafe"        \
TEST_INPUT="$UNICODE_DIR"           \
run_test

# Test 25: Single character name
SINGLE_DIR="$TEST_DIR/a"
mkdir -p "$SINGLE_DIR"
TEST_NAME="Single character name" \
TEST_EXPECTED="a"                 \
TEST_INPUT="$SINGLE_DIR"          \
run_test

# Test 26: Single uppercase character
SINGLE_UPPER_DIR="$TEST_DIR/Z"
mkdir -p "$SINGLE_UPPER_DIR"
TEST_NAME="Single uppercase char to lowercase" \
TEST_EXPECTED="z"                              \
TEST_INPUT="$SINGLE_UPPER_DIR"                 \
run_test

# Test 27: Dots and dashes mixed
DOT_DASH_DIR="$TEST_DIR/my.project-name.v1"
mkdir -p "$DOT_DASH_DIR"
TEST_NAME="Dots and dashes mixed"  \
TEST_EXPECTED="my.project-name.v1" \
TEST_INPUT="$DOT_DASH_DIR"         \
run_test

# Test 28: CamelCase
CAMEL_DIR="$TEST_DIR/MyProjectName"
mkdir -p "$CAMEL_DIR"
TEST_NAME="CamelCase to lowercase" \
TEST_EXPECTED="myprojectname"      \
TEST_INPUT="$CAMEL_DIR"            \
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
