#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Select All Templates and Extensions
#
# Proves that:
#   1) Every template (with all its extensions) can be selected and compiled
#   2) ALL templates and extensions can be selected simultaneously
#
# Dependencies are auto-resolved: if a template or extension requires another
# template, it is automatically included in the selection.
#
# This test does NOT require Docker — it uses --dryrun to verify that the
# selection DSL parses and compiles without errors.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Select All Templates and Extensions ==="

FAILED=0
TEST_NUM=0

# ---------------------------------------------------------------------------
# Helper: find the codingbooth binary (same logic as run_coding_booth)
# ---------------------------------------------------------------------------
find_booth() {
  local check_dir="$SCRIPT_DIR"
  for _ in 1 2 3 4 5; do
    if [[ -x "$check_dir/codingbooth" ]]; then
      echo "$check_dir/codingbooth"
      return
    fi
    check_dir="$(dirname "$check_dir")"
  done
  echo "ERROR: Could not find codingbooth" >&2
  return 1
}

BOOTH="$(find_booth)"

# ---------------------------------------------------------------------------
# Parse `template list --full` to discover all templates and extensions.
#
# Produces two arrays:
#   TEMPLATES[i]   = template name
#   EXTENSIONS[i]  = "ext1+ext2+..." (empty string if none)
# ---------------------------------------------------------------------------
declare -a TEMPLATES=()
declare -a EXTENSIONS=()

current_tmpl=""
current_exts=""

while IFS= read -r line; do
  # Template line: starts with exactly 2 spaces then a lowercase letter
  if [[ "$line" =~ ^\ \ ([a-z][a-z0-9_-]*)\ + ]]; then
    # Flush previous template
    if [[ -n "$current_tmpl" ]]; then
      TEMPLATES+=("$current_tmpl")
      EXTENSIONS+=("$current_exts")
    fi
    current_tmpl="${BASH_REMATCH[1]}"
    current_exts=""
  # Extension line: starts with "    + "
  elif [[ "$line" =~ ^\ \ \ \ \+\ ([a-z][a-z0-9_-]*) ]]; then
    ext="${BASH_REMATCH[1]}"
    # Strip trailing * (auto-select marker)
    ext="${ext%\*}"
    if [[ -z "$current_exts" ]]; then
      current_exts="$ext"
    else
      current_exts="${current_exts}+${ext}"
    fi
  fi
done < <("$BOOTH" template list --full 2>&1)

# Flush last template
if [[ -n "$current_tmpl" ]]; then
  TEMPLATES+=("$current_tmpl")
  EXTENSIONS+=("$current_exts")
fi

TOTAL_TEMPLATES=${#TEMPLATES[@]}
echo "Discovered $TOTAL_TEMPLATES templates."

if [[ $TOTAL_TEMPLATES -eq 0 ]]; then
  echo "ERROR: No templates discovered — cannot run test."
  exit 1
fi

# ---------------------------------------------------------------------------
# try_select: attempt config --no-tui --dryrun, auto-adding missing deps.
#
# If the command fails with "requires X which is not selected", X is appended
# to the DSL and the command is retried (up to 10 rounds for deep chains).
# Returns 0 on success, 1 on failure (with output in $SELECT_OUTPUT).
# ---------------------------------------------------------------------------
SELECT_OUTPUT=""
try_select() {
  local dsl="$1"
  local max_retries=10

  for ((attempt=0; attempt<max_retries; attempt++)); do
    SELECT_OUTPUT=$("$BOOTH" config --no-tui --dryrun --select "$dsl" 2>&1) && return 0

    # Parse missing dependency from error message
    local missing
    missing=$(echo "$SELECT_OUTPUT" \
      | grep -oP 'requires "\K[^"]+(?=" which is not selected)' \
      | head -1)

    if [[ -z "$missing" ]]; then
      # Not a dependency error — genuine failure
      return 1
    fi

    # Add missing dependency to the DSL
    dsl="${dsl}/${missing}"
  done

  # Exhausted retries
  return 1
}

# ---------------------------------------------------------------------------
# Test 1: Each template can be individually selected (with all its extensions)
#
# Dependencies are resolved automatically via try_select.
# ---------------------------------------------------------------------------
echo ""
echo "--- Test: Individual template selection ---"

for i in "${!TEMPLATES[@]}"; do
  tmpl="${TEMPLATES[$i]}"
  exts="${EXTENSIONS[$i]}"

  dsl="$tmpl"
  if [[ -n "$exts" ]]; then
    dsl="${tmpl}+${exts}"
  fi

  TEST_NUM=$((TEST_NUM + 1))

  if try_select "$dsl"; then
    print_test_result "true" "$0" "$TEST_NUM" "Individual select: $tmpl (${exts:-no extensions})"
  else
    print_test_result "false" "$0" "$TEST_NUM" "Individual select: $tmpl (${exts:-no extensions})"
    echo "  Output: $SELECT_OUTPUT"
    FAILED=$((FAILED + 1))
  fi
done

# ---------------------------------------------------------------------------
# Test 2: ALL templates and extensions selected simultaneously
#
# Known param conflicts are resolved by aligning parameter values:
#   - conda (standalone) defaults PYTHON_VERSION=3.12, but python defaults
#     to a newer version. We pass conda's PYTHON_VERSION to match python's.
# ---------------------------------------------------------------------------
echo ""
echo "--- Test: Select ALL templates simultaneously ---"

# Discover python's default PYTHON_VERSION for conflict resolution
PYTHON_VERSION=$("$BOOTH" template show python 2>&1 \
  | grep "PYTHON_VERSION" | head -1 \
  | sed -E 's/.*default: ([^ ]+).*/\1/')

# Build the combined DSL
COMBINED_DSL=""
for i in "${!TEMPLATES[@]}"; do
  tmpl="${TEMPLATES[$i]}"
  exts="${EXTENSIONS[$i]}"

  part="$tmpl"

  # Resolve conda param conflict: align with python's PYTHON_VERSION
  if [[ "$tmpl" == "conda" && -n "$PYTHON_VERSION" ]]; then
    part="conda:${PYTHON_VERSION}"
  fi

  if [[ -n "$exts" ]]; then
    part="${part}+${exts}"
  fi

  if [[ -z "$COMBINED_DSL" ]]; then
    COMBINED_DSL="$part"
  else
    COMBINED_DSL="${COMBINED_DSL}/${part}"
  fi
done

TEST_NUM=$((TEST_NUM + 1))

if output=$("$BOOTH" config --no-tui --dryrun --select "$COMBINED_DSL" 2>&1); then
  # Verify the output contains both config.toml and Boothfile sections
  has_config=false
  has_boothfile=false
  if echo "$output" | grep -q "=== config.toml ==="; then
    has_config=true
  fi
  if echo "$output" | grep -q "=== Boothfile ==="; then
    has_boothfile=true
  fi

  if $has_config && $has_boothfile; then
    print_test_result "true" "$0" "$TEST_NUM" "ALL $TOTAL_TEMPLATES templates selected simultaneously"
  else
    print_test_result "false" "$0" "$TEST_NUM" "ALL templates selected but output missing sections (config=$has_config, boothfile=$has_boothfile)"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "$TEST_NUM" "ALL $TOTAL_TEMPLATES templates selected simultaneously"
  echo "  Output: $output"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
TOTAL_TESTS=$TEST_NUM
PASSED=$((TOTAL_TESTS - FAILED))
echo "Results: ${PASSED}/${TOTAL_TESTS} passed ($TOTAL_TEMPLATES templates individually + 1 combined)"

exit $FAILED
