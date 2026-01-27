#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Master test runner script for all workspace examples
# Runs all example test suites and reports overall results

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=0
failed_suites=()
total_suites=0
skipped_suites=()

echo "========================================"
echo "Running All Example Tests"
echo "========================================"
echo ""

# Find all directories with run-automatic-on-host-test.sh
for example_dir in "$SCRIPT_DIR"/*/; do
    example_name=$(basename "$example_dir")
    test_runner="$example_dir/run-automatic-on-host-test.sh"
    
    # Skip if no test runner exists
    if [ ! -f "$test_runner" ]; then
        continue
    fi
    
    # Check if there are any test0*.sh files
    test_count=$(find "$example_dir" -maxdepth 1 -name "test0*.sh" 2>/dev/null | wc -l)
    if [ "$test_count" -eq 0 ]; then
        skipped_suites+=("$example_name (no tests)")
        continue
    fi
    
    echo "----------------------------------------"
    echo "Running $example_name Tests ($test_count test(s))"
    echo "----------------------------------------"
    total_suites=$((total_suites + 1))
    if ! (cd "$example_dir" && ./run-automatic-on-host-test.sh); then
        failed=1
        failed_suites+=("$example_name")
    fi
    echo ""
done

# Summary
echo "========================================"
echo "Example Test Summary"
echo "========================================"
num_failed=${#failed_suites[@]}
num_skipped=${#skipped_suites[@]}

if [ $failed -eq 0 ]; then
    echo "✓ All $total_suites example test suites passed!"
else
    echo "✗ $num_failed out of $total_suites example test suites FAILED."
    echo "Failed suites:"
    for suite in "${failed_suites[@]}"; do
        echo "  - $suite"
    done
fi

if [ $num_skipped -gt 0 ]; then
    echo ""
    echo "Skipped $num_skipped suites:"
    for suite in "${skipped_suites[@]}"; do
        echo "  - $suite"
    done
fi
echo ""

exit $failed
