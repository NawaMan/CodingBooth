#!/bin/bash

# Go unit test runner script
# Runs only Go unit tests in the workspace (skipping integration tests)

set -e  # Exit on first failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$SCRIPT_DIR/run-go-unit-tests.log"

# Redirect output to log file and stdout
exec > >(tee -i "$LOG_FILE") 2>&1

echo "========================================"
echo "Running Go Unit Tests Only"
echo "========================================"
echo "Skipping tests matching: TestIntegration_.*"
echo ""

cd "$WORKSPACE_ROOT"

echo "----------------------------------------"
echo "Running: go test -v -skip \"TestIntegration_.*\" ./..."
echo "----------------------------------------"
echo ""

if go test -v -skip "TestIntegration_.*" ./...; then
    echo ""
    echo "✓ Go unit tests passed!"
    echo "========================================"
    exit 0
else
    echo ""
    echo "✗ Go unit tests FAILED."
    echo "========================================"
    exit 1
fi
