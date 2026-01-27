#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Common utilities for unit tests

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
  COLOR_CMD='\033[1;36m'    # Cyan bold for commands
  COLOR_BOOTH='\033[1;33m'  # Yellow bold for coding-booth
  COLOR_RESET='\033[0m'
else
  COLOR_CMD=''
  COLOR_BOOTH=''
  COLOR_RESET=''
fi

# Run a command with visible output of what's being executed
# Usage: run_cmd <command...>
# Example: run_cmd ls -la
# Note: Command trace goes to stderr so it doesn't interfere with captured stdout
run_cmd() {
  echo -e "${COLOR_CMD}> $*${COLOR_RESET}" >&2
  "$@"
}

# Run a coding-booth command with highlighted output
# Usage: run_coding_booth [args...]
# Example: run_coding_booth --variant base -- echo hello
# The path to coding-booth is auto-detected relative to the test script
# Note: Command trace goes to stderr so it doesn't interfere with captured stdout
run_coding_booth() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

  # Find coding-booth relative to the test location
  local booth_path=""
  local check_dir="$script_dir"
  for _ in 1 2 3 4 5; do
    if [[ -x "$check_dir/coding-booth" ]]; then
      booth_path="$check_dir/coding-booth"
      break
    fi
    check_dir="$(dirname "$check_dir")"
  done

  if [[ -z "$booth_path" ]]; then
    echo "ERROR: Could not find coding-booth" >&2
    return 1
  fi

  echo -e "${COLOR_BOOTH}> coding-booth $*${COLOR_RESET}" >&2
  "$booth_path" "$@"
}

# Normalize output for cross-platform comparison
# - Strips .exe extension from binary name
# - Converts Windows backslashes to forward slashes
# - Removes single quotes around Windows paths in -v mounts
# - Normalizes MSYS paths (/c/Users → C:/Users)
# - Masks UID/GID values to XXXXX for environment independence
normalize_output() {
    sed -E \
        -e 's/workspace\.exe/workspace/g' \
        -e 's|\\|/|g' \
        -e "s|-v '([^']+)'|-v \1|g" \
        -e 's|/c/|C:/|gi' \
        -e 's|/C/|C:/|g' \
        -e "s/HOST_UID=[0-9]+/HOST_UID=XXXXX/g" \
        -e "s/HOST_GID=[0-9]+/HOST_GID=XXXXX/g" \
        -e "s/HOST_UID:[[:space:]]+[0-9]+/HOST_UID:       XXXXX/g" \
        -e "s/HOST_GID:[[:space:]]+[0-9]+/HOST_GID:       XXXXX/g"
}

script_relative_path() {
  local script_abs="${1:-$0}"
  local root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  script_abs=$(realpath "$script_abs")
  root=$(realpath "$root")
  echo "${script_abs#${root}/tests/}"
}

# Print standardized test result
# Usage: print_test_result <success> <script_path> <test_number> <description>
#   success: "true" or "false"
#   script_path: path to test script (usually $0)
#   test_number: test number
#   description: test description
print_test_result() {
  local success="$1"
  local script_path="$2"
  local test_number="$3"
  local description="$4"
  
  local relative_path=$(script_relative_path "$script_path")
  local icon="✅"
  
  if [[ "$success" != "true" ]]; then
    icon="❌"
  fi
  
  echo "${icon} ${relative_path}: Test ${test_number}: ${description}"
}
