#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Go integration test runner script
# Runs only Go integration tests in the workspace (matching TestIntegration_.*)

set -e  # Exit on first failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$SCRIPT_DIR/run-go-integration-tests.log"

# Redirect output to log file and stdout
exec > >(tee -i "$LOG_FILE") 2>&1

echo "========================================"
echo "Running Go Integration Tests Only"
echo "========================================"
echo "Running tests matching: TestIntegration_.*"
echo ""

cd "$WORKSPACE_ROOT/cli"

echo "----------------------------------------"
echo "Running: go test -v -run \"TestIntegration_.*\" ./..."
echo "----------------------------------------"
echo ""

if go test -v -run "TestIntegration_.*" ./...; then
    echo ""
    echo "✓ Go integration tests passed!"
    echo "========================================"
    exit 0
else
    echo ""
    echo "✗ Go integration tests FAILED."
    echo "========================================"
    exit 1
fi
