#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: Verify Python version can be overridden via --build-arg

set -euo pipefail

source ../common--source.sh

# Create temporary test directory
TEST_DIR=$(mktemp -d)
BOOTH_DIR="$TEST_DIR/.booth"
mkdir -p "$BOOTH_DIR"

# Cleanup function
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Create Dockerfile with Python version override support
cat > "$BOOTH_DIR/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

ARG PYTHON_VERSION=${PYTHON_VERSION:-3.12}
RUN python--setup.sh "${PYTHON_VERSION}"
EOF

# =============================================================================
# TEST 1: Default Python version (3.12)
# =============================================================================
DEFAULT_OUTPUT=$(../../coding-booth --code "$TEST_DIR" --variant base --silence-build -- 'python --version' 2>&1) || {
  print_test_result "false" "$0" "1" "Failed to run with default Python version"
  echo "Output: $DEFAULT_OUTPUT"
  exit 1
}

if echo "$DEFAULT_OUTPUT" | grep -qE '^Python 3\.12\.[0-9]+'; then
  print_test_result "true" "$0" "1" "Default Python version is 3.12.x: $DEFAULT_OUTPUT"
else
  print_test_result "false" "$0" "1" "Default Python version is not 3.12.x"
  echo "Output: $DEFAULT_OUTPUT"
  exit 1
fi

# =============================================================================
# TEST 2: Override Python version to 3.11
# =============================================================================
OVERRIDE_OUTPUT=$(../../coding-booth --code "$TEST_DIR" --variant base --silence-build --build-arg PYTHON_VERSION=3.11 -- 'python --version' 2>&1) || {
  print_test_result "false" "$0" "2" "Failed to run with Python 3.11 override"
  echo "Output: $OVERRIDE_OUTPUT"
  exit 1
}

if echo "$OVERRIDE_OUTPUT" | grep -qE '^Python 3\.11\.[0-9]+'; then
  print_test_result "true" "$0" "2" "Python version override to 3.11 works: $OVERRIDE_OUTPUT"
else
  print_test_result "false" "$0" "2" "Python version override to 3.11 failed"
  echo "Output: $OVERRIDE_OUTPUT"
  exit 1
fi

# =============================================================================
# TEST 3: Override Python version to 3.10
# =============================================================================
OVERRIDE_OUTPUT_310=$(../../coding-booth --code "$TEST_DIR" --variant base --silence-build --build-arg PYTHON_VERSION=3.10 -- 'python --version' 2>&1) || {
  print_test_result "false" "$0" "3" "Failed to run with Python 3.10 override"
  echo "Output: $OVERRIDE_OUTPUT_310"
  exit 1
}

if echo "$OVERRIDE_OUTPUT_310" | grep -qE '^Python 3\.10\.[0-9]+'; then
  print_test_result "true" "$0" "3" "Python version override to 3.10 works: $OVERRIDE_OUTPUT_310"
else
  print_test_result "false" "$0" "3" "Python version override to 3.10 failed"
  echo "Output: $OVERRIDE_OUTPUT_310"
  exit 1
fi

echo ""
echo "All Python version override tests passed!"
