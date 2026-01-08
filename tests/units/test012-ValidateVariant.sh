#!/bin/bash
set -euo pipefail

# Source workspace to get the ValidateVariant function
# Set SKIP_MAIN to prevent the main script from executing
export SKIP_MAIN=true
source ../../workspace
source ../common--source.sh

# Test counter
test_count=0
pass_count=0
fail_count=0

SCRIPT_TITLE=$(script_relative_path "$0")

# Test helper function for successful cases
run_test() {
  local test_name="$TEST_NAME"
  local expected_variant="$TEST_EXPECTED_VARIANT"
  local expected_notebook="$TEST_EXPECTED_NOTEBOOK"
  local expected_vscode="$TEST_EXPECTED_VSCODE"
  local expected_desktop="$TEST_EXPECTED_DESKTOP"
  
  test_count=$((test_count + 1))
  
  # Call ValidateVariant
  ValidateVariant >/dev/null 2>&1
  
  # Check results
  local variant_match=false
  local notebook_match=false
  local vscode_match=false
  local desktop_match=false
  
  [[ "${VARIANT}" == "$expected_variant" ]] && variant_match=true
  [[ "${HAS_NOTEBOOK}" == "$expected_notebook" ]] && notebook_match=true
  [[ "${HAS_VSCODE}" == "$expected_vscode" ]] && vscode_match=true
  [[ "${HAS_DESKTOP}" == "$expected_desktop" ]] && desktop_match=true
  
  if $variant_match && $notebook_match && $vscode_match && $desktop_match; then
    echo "✅ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "❌ ${SCRIPT_TITLE}: Test $test_count: $test_name"
    echo "-------------------------------------------------------------------------------"
    ! $variant_match && echo "  VARIANT: expected=$expected_variant, actual=${VARIANT}"
    ! $notebook_match && echo "  HAS_NOTEBOOK: expected=$expected_notebook, actual=${HAS_NOTEBOOK}"
    ! $vscode_match && echo "  HAS_VSCODE: expected=$expected_vscode, actual=${HAS_VSCODE}"
    ! $desktop_match && echo "  HAS_DESKTOP: expected=$expected_desktop, actual=${HAS_DESKTOP}"
    echo "-------------------------------------------------------------------------------"
    fail_count=$((fail_count + 1))
  fi
}

# Test 1: base variant (no aliases)
VARIANT="base"
TEST_NAME="base variant"                 \
TEST_EXPECTED_VARIANT="base"             \
TEST_EXPECTED_NOTEBOOK="false"           \
TEST_EXPECTED_VSCODE="false"             \
TEST_EXPECTED_DESKTOP="false"            \
run_test

# Test 2: ide-notebook variant (no aliases)
VARIANT="ide-notebook"
TEST_NAME="ide-notebook variant"         \
TEST_EXPECTED_VARIANT="ide-notebook"     \
TEST_EXPECTED_NOTEBOOK="true"            \
TEST_EXPECTED_VSCODE="false"             \
TEST_EXPECTED_DESKTOP="false"            \
run_test

# Test 3: ide-codeserver variant (no aliases)
VARIANT="ide-codeserver"
TEST_NAME="ide-codeserver variant"       \
TEST_EXPECTED_VARIANT="ide-codeserver"   \
TEST_EXPECTED_NOTEBOOK="true"            \
TEST_EXPECTED_VSCODE="true"              \
TEST_EXPECTED_DESKTOP="false"            \
run_test

# Test 4: desktop-xfce variant (no aliases)
VARIANT="desktop-xfce"
TEST_NAME="desktop-xfce variant"         \
TEST_EXPECTED_VARIANT="desktop-xfce"     \
TEST_EXPECTED_NOTEBOOK="true"            \
TEST_EXPECTED_VSCODE="true"              \
TEST_EXPECTED_DESKTOP="true"             \
run_test

# Test 5: desktop-kde variant (no aliases)
VARIANT="desktop-kde"
TEST_NAME="desktop-kde variant"          \
TEST_EXPECTED_VARIANT="desktop-kde"      \
TEST_EXPECTED_NOTEBOOK="true"            \
TEST_EXPECTED_VSCODE="true"              \
TEST_EXPECTED_DESKTOP="true"             \
run_test

# Test 6: console alias -> base
VARIANT="console"
TEST_NAME="console alias -> base"        \
TEST_EXPECTED_VARIANT="base"             \
TEST_EXPECTED_NOTEBOOK="false"           \
TEST_EXPECTED_VSCODE="false"             \
TEST_EXPECTED_DESKTOP="false"            \
run_test

# Test 7: default alias -> ide-codeserver
VARIANT="default"
TEST_NAME="default alias -> ide-codeserver" \
TEST_EXPECTED_VARIANT="ide-codeserver"      \
TEST_EXPECTED_NOTEBOOK="true"               \
TEST_EXPECTED_VSCODE="true"                 \
TEST_EXPECTED_DESKTOP="false"               \
run_test

# Test 8: ide alias -> ide-codeserver
VARIANT="ide"
TEST_NAME="ide alias -> ide-codeserver"  \
TEST_EXPECTED_VARIANT="ide-codeserver"   \
TEST_EXPECTED_NOTEBOOK="true"            \
TEST_EXPECTED_VSCODE="true"              \
TEST_EXPECTED_DESKTOP="false"            \
run_test

# Test 9: desktop alias -> desktop-xfce
VARIANT="desktop"
TEST_NAME="desktop alias -> desktop-xfce" \
TEST_EXPECTED_VARIANT="desktop-xfce"      \
TEST_EXPECTED_NOTEBOOK="true"             \
TEST_EXPECTED_VSCODE="true"               \
TEST_EXPECTED_DESKTOP="true"              \
run_test

# Test 10: notebook alias -> ide-notebook
VARIANT="notebook"
TEST_NAME="notebook alias -> ide-notebook" \
TEST_EXPECTED_VARIANT="ide-notebook"       \
TEST_EXPECTED_NOTEBOOK="true"              \
TEST_EXPECTED_VSCODE="false"               \
TEST_EXPECTED_DESKTOP="false"              \
run_test

# Test 11: codeserver alias -> ide-codeserver
VARIANT="codeserver"
TEST_NAME="codeserver alias -> ide-codeserver" \
TEST_EXPECTED_VARIANT="ide-codeserver"         \
TEST_EXPECTED_NOTEBOOK="true"                  \
TEST_EXPECTED_VSCODE="true"                    \
TEST_EXPECTED_DESKTOP="false"                  \
run_test

# Test 12: xfce alias -> desktop-xfce
VARIANT="xfce"
TEST_NAME="xfce alias -> desktop-xfce"   \
TEST_EXPECTED_VARIANT="desktop-xfce"     \
TEST_EXPECTED_NOTEBOOK="true"            \
TEST_EXPECTED_VSCODE="true"              \
TEST_EXPECTED_DESKTOP="true"             \
run_test

# Test 13: kde alias -> desktop-kde
VARIANT="kde"
TEST_NAME="kde alias -> desktop-kde"     \
TEST_EXPECTED_VARIANT="desktop-kde"      \
TEST_EXPECTED_NOTEBOOK="true"            \
TEST_EXPECTED_VSCODE="true"              \
TEST_EXPECTED_DESKTOP="true"             \
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
echo "NOTE: Error cases (invalid variants) are not tested because the function"
echo "      calls 'exit 1' which would terminate this script."
echo "==============================================================================="

if [ $fail_count -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed!"
  exit 1
fi
