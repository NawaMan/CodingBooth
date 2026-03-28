#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Runs all test*.sh scripts in this directory (excluding test-helpers--source.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERBOSE=""
for arg in "$@"; do case "$arg" in --verbose) VERBOSE="--verbose" ;; esac; done

# Collect test files
declare -a test_files=()
for test_file in "$SCRIPT_DIR"/test*.sh; do
    name=$(basename "$test_file" .sh)
    [[ "$name" == "test-helpers--source" ]] && continue
    test_files+=("$test_file")
done

if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "No test files found."
    exit 0
fi

echo "==============================================================================="
echo "Running Config Tests"
echo "==============================================================================="
echo "Tests to run: ${#test_files[@]}"
echo ""

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
FAIL_TESTS=()

OVERALL_START=$(date +%s)

for test_file in "${test_files[@]}"; do
    name=$(basename "$test_file" .sh)
    TEST_COUNT=$((TEST_COUNT + 1))

    echo "-------------------------------------------------------------------------------"

    if (cd "$SCRIPT_DIR" && bash "$test_file" $VERBOSE); then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("$name")
    fi
    echo ""
done

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

echo "========================================"
echo "  Config Test Summary"
echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Failed: ${FAIL_COUNT}"
echo "  Duration: ${OVERALL_DURATION}s"
echo "========================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for T in "${FAIL_TESTS[@]}"; do
        echo -e "  \u274c ${T}"
    done
    echo ""
    exit 1
fi

echo -e "\033[32m  All config tests passed!\033[0m"
echo ""
