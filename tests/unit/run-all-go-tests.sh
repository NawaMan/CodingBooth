#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Go test runner script
# Runs all Go tests in the workspace (Unit + Integration + Docker)

set -e  # Exit on first failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$SCRIPT_DIR/run-all-go-tests.log"

# Redirect output to log file and stdout
exec > >(tee -i "$LOG_FILE") 2>&1

failed=0
failed_suites=()
total_suites=0

echo "========================================"
echo "Running All Go Tests"
echo "========================================"
echo ""

cd "$SCRIPT_DIR"

# 1. Run Go Unit Tests
total_suites=$((total_suites + 1))
if ./run-go-unit-tests.sh; then
    echo ""
else
    failed=1
    failed_suites+=("go unit tests")
fi
echo ""

# 2. Run Go Integration Tests
total_suites=$((total_suites + 1))
if ./run-go-integration-tests.sh; then
    echo ""
else
    failed=1
    failed_suites+=("go integration tests")
fi
echo ""

# 3. Run Docker Integration Tests
total_suites=$((total_suites + 1))
# Note: run-docker-tests.sh might need to be called from correct dir or generic way
# Assuming it works as called before but using SCRIPT_DIR current dir
if ./run-docker-tests.sh --all-auto; then
    echo ""
    echo "✓ Docker integration tests passed!"
else
    failed=1
    failed_suites+=("docker integration tests")
fi
echo ""

# Summary
echo "========================================"
echo "Go Test Suite Summary"
echo "========================================"
num_failed=${#failed_suites[@]}

if [ $failed -eq 0 ]; then
    echo "✓ All $total_suites test suites passed!"
    echo "========================================"
    exit 0
else
    echo "✗ $num_failed out of $total_suites test suites FAILED."
    echo "Failed suites:"
    for suite in "${failed_suites[@]}"; do
        echo "  - $suite"
    done
    echo "========================================"
    exit 1
fi
