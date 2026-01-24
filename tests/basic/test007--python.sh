#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: Verify Python is installed and functional

set -euo pipefail

source ../common--source.sh

# =============================================================================
# TEST 1: Python is installed and accessible
# =============================================================================
PYTHON_OUTPUT=$(../../coding-booth --variant base --silence-build -- 'python --version' 2>&1) || {
  print_test_result "false" "$0" "1" "Python command failed"
  echo "Output: $PYTHON_OUTPUT"
  exit 1
}

if echo "$PYTHON_OUTPUT" | grep -qE '^Python [0-9]+\.[0-9]+\.[0-9]+'; then
  print_test_result "true" "$0" "1" "Python is installed: $PYTHON_OUTPUT"
else
  print_test_result "false" "$0" "1" "Python version output unexpected"
  echo "Output: $PYTHON_OUTPUT"
  exit 1
fi

# =============================================================================
# TEST 2: pip is installed and accessible
# =============================================================================
PIP_OUTPUT=$(../../coding-booth --variant base --silence-build -- 'pip --version' 2>&1) || {
  print_test_result "false" "$0" "2" "pip command failed"
  echo "Output: $PIP_OUTPUT"
  exit 1
}

if echo "$PIP_OUTPUT" | grep -qE '^pip [0-9]+'; then
  print_test_result "true" "$0" "2" "pip is installed"
else
  print_test_result "false" "$0" "2" "pip version output unexpected"
  echo "Output: $PIP_OUTPUT"
  exit 1
fi

# =============================================================================
# TEST 3: Python can import standard library
# =============================================================================
IMPORT_OUTPUT=$(../../coding-booth --variant base --silence-build -- 'python -c "import sys, os, json; print(\"OK\")"' 2>&1) || {
  print_test_result "false" "$0" "3" "Python import failed"
  echo "Output: $IMPORT_OUTPUT"
  exit 1
}

if echo "$IMPORT_OUTPUT" | grep -q "OK"; then
  print_test_result "true" "$0" "3" "Python can import standard library modules"
else
  print_test_result "false" "$0" "3" "Python import test failed"
  echo "Output: $IMPORT_OUTPUT"
  exit 1
fi

# =============================================================================
# TEST 4: Python environment variables are set
# =============================================================================
ENV_OUTPUT=$(../../coding-booth --variant base --silence-build -- 'echo $CB_PY_VERSION' 2>&1) || {
  print_test_result "false" "$0" "4" "Failed to get CB_PY_VERSION"
  exit 1
}

if echo "$ENV_OUTPUT" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
  print_test_result "true" "$0" "4" "CB_PY_VERSION is set: $ENV_OUTPUT"
else
  print_test_result "false" "$0" "4" "CB_PY_VERSION not set or invalid"
  echo "Output: $ENV_OUTPUT"
  exit 1
fi

echo ""
echo "All Python tests passed!"
