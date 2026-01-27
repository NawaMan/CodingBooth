#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Manual test runner script
# Runs all manual test suites in the tests/manual directory

set -e  # Exit on first failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=0
failed_suites=()
total_suites=0

echo "========================================"
echo "Running All Manual Test Suites"
echo "========================================"
echo ""

# Run docker-build-color manual test
echo "----------------------------------------"
echo "Running Docker Build Color Manual Test"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/manual" && ./run-docker-build-color-manual-test.sh); then
    failed=1
    failed_suites+=("docker-build-color")
fi
echo ""

# Run docker-interactive manual test
echo "----------------------------------------"
echo "Running Docker Interactive Manual Test"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/manual" && ./run-docker-interactive-manual-test.sh); then
    failed=1
    failed_suites+=("docker-interactive")
fi
echo ""

# Run colored-prompt manual test
echo "----------------------------------------"
echo "Running Colored Prompt Manual Test"
echo "----------------------------------------"
total_suites=$((total_suites + 1))
if ! (cd "$SCRIPT_DIR/manual" && ./run-colored-prompt-manual-test.sh); then
    failed=1
    failed_suites+=("colored-prompt")
fi
echo ""

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
num_failed=${#failed_suites[@]}

if [ $failed -eq 0 ]; then
    echo "✓ All $total_suites manual test suites passed!"
else
    echo "✗ $num_failed out of $total_suites manual test suites FAILED."
    echo "Failed suites:"
    for suite in "${failed_suites[@]}"; do
        echo "  - $suite"
    done
fi
echo ""

exit $failed
