#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Manual test runner script
# Auto-discovers and runs all run-*-manual-test.sh scripts in tests/manual/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANUAL_DIR="$SCRIPT_DIR/manual"

failed=0
failed_suites=()
total_suites=0

echo "========================================"
echo "Running All Manual Test Suites"
echo "========================================"
echo ""

for test_file in "$MANUAL_DIR"/run-*-manual-test.sh; do
    [[ -f "$test_file" ]] || continue

    name=$(basename "$test_file" .sh)
    # Strip "run-" prefix and "-manual-test" suffix for display
    label="${name#run-}"
    label="${label%-manual-test}"

    echo "----------------------------------------"
    echo "Running: $label"
    echo "----------------------------------------"
    total_suites=$((total_suites + 1))

    if (cd "$MANUAL_DIR" && ./"$(basename "$test_file")"); then
        echo -e "\033[1;32m✔ $label passed\033[0m"
    else
        failed=1
        failed_suites+=("$label")
        echo -e "\033[1;31m✘ $label FAILED\033[0m"
    fi
    echo ""
done

# Summary
echo "========================================"
echo "Manual Test Summary"
echo "========================================"
num_failed=${#failed_suites[@]}

if [ $failed -eq 0 ]; then
    echo -e "\033[1;32m✓ All $total_suites manual test suites passed!\033[0m"
else
    echo -e "\033[1;31m✗ $num_failed out of $total_suites manual test suites FAILED.\033[0m"
    echo "Failed suites:"
    for suite in "${failed_suites[@]}"; do
        echo -e "  \033[1;31m- $suite\033[0m"
    done
fi
echo ""

exit $failed
