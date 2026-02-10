#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Runs all test*.sh scripts in this directory.
# Use --heavy to also run heavy tests (desktops, IDEs, browsers).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERBOSE=""
HEAVY=false
for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE="--verbose" ;;
        --heavy)   HEAVY=true ;;
    esac
done

# Collect test files
declare -a test_files=()
for test_file in "$SCRIPT_DIR"/test*.sh; do
    name=$(basename "$test_file" .sh)
    # Skip heavy tests unless --heavy is passed
    if [[ "$HEAVY" != "true" ]] && [[ "$name" == *"-heavy-"* ]]; then
        echo "Skipping heavy test: $name (use --heavy to include)"
        continue
    fi
    test_files+=("$test_file")
done

if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "No test files found."
    exit 0
fi

echo "==============================================================================="
echo "Running Template Tests"
echo "==============================================================================="
echo "Tests to run: ${#test_files[@]}"
echo ""

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAIL_TESTS=()
SKIP_TESTS=()

OVERALL_START=$(date +%s)

for test_file in "${test_files[@]}"; do
    name=$(basename "$test_file" .sh)
    TEST_COUNT=$((TEST_COUNT + 1))

    echo "-------------------------------------------------------------------------------"

    set +e
    (cd "$SCRIPT_DIR" && bash "$test_file" $VERBOSE)
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    elif [[ $rc -eq 2 ]]; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
        SKIP_TESTS+=("$name")
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("$name")
    fi
    echo ""
done

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

echo "========================================"
echo "  Template Test Summary"
echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Skipped: ${SKIP_COUNT}   Failed: ${FAIL_COUNT}"
echo "  Duration: ${OVERALL_DURATION}s"
echo "========================================"

if [[ ${SKIP_COUNT} -gt 0 ]]; then
    echo ""
    echo "Skipped tests:"
    for T in "${SKIP_TESTS[@]}"; do
        echo -e "  \u23ed  ${T}"
    done
fi

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for T in "${FAIL_TESTS[@]}"; do
        echo -e "  \u274c ${T}"
    done
    echo ""
    exit 1
fi

echo ""
echo -e "\033[32m  All template tests passed!\033[0m"
echo ""
