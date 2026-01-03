#!/bin/bash

# Go test runner script
# Runs all Go tests in the workspace

set -e  # Exit on first failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

failed=0
failed_suites=()
total_suites=0

echo "========================================"
echo "Running All Go Tests"
echo "========================================"
echo ""

# Run all Go tests with verbose output
echo "----------------------------------------"
echo "Running: go test -v ./..."
echo "----------------------------------------"
echo ""

cd "$WORKSPACE_ROOT"

total_suites=$((total_suites + 1))
if go test -v ./...; then
    echo ""
    echo "✓ Go unit tests passed!"
else
    failed=1
    failed_suites+=("go unit tests")
fi
echo ""

# Run Docker manual tests
echo "----------------------------------------"
echo "Running Docker Manual Tests"
echo "----------------------------------------"
echo ""

cd "$SCRIPT_DIR"

# Run Docker integration tests
echo "----------------------------------------"
echo "Running Docker Integration Tests"
echo "----------------------------------------"
echo ""

total_suites=$((total_suites + 1))
if ./run-docker-integration-tests.sh --all-auto; then
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
