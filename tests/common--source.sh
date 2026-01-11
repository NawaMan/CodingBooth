#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Common utilities for unit tests

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
