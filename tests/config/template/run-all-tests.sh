#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Runs all test*.sh scripts in this directory.
# Use --heavy to also run heavy tests (desktops, IDEs, browsers).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Each test runs through run_test_script, which fails a test that bash 3.2 let
# exit 0 after it died on an unbound variable (see run-test-script--source.sh).
source "${SCRIPT_DIR}/../../run-test-script--source.sh"

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

# Retry a failed test once, immediately. Every test here builds a real image, so
# an archive 503 or a registry blip fails it for reasons a second attempt does
# not have — and without this, run-automate-tests.sh's only answer is to rerun
# the whole suite. A pass that needed the retry is still listed at the end. 2 is
# `skip` (test-helpers--source.sh), which no retry changes.
RETRIED_TESTS=()

OVERALL_START=$(date +%s)

for test_file in "${test_files[@]}"; do
    name=$(basename "$test_file" .sh)
    TEST_COUNT=$((TEST_COUNT + 1))

    echo "-------------------------------------------------------------------------------"

    set +e
    (cd "$SCRIPT_DIR" && run_test_script bash "$test_file" $VERBOSE)
    rc=$?
    if [[ $rc -ne 0 && $rc -ne 2 ]]; then
        echo "⚠️  FAILED: ${name} — retrying once"
        RETRIED_TESTS+=("$name")
        (cd "$SCRIPT_DIR" && run_test_script bash "$test_file" $VERBOSE)
        rc=$?
        [[ $rc -eq 0 ]] && echo "✅ PASSED after retry: ${name}"
    fi
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

# "  - <name>", as every suite runner prints its lists: run-automate-tests.sh
# reads failures and flakes from exactly that shape. (Not `echo -e "\u274c"`:
# macOS's bash 3.2 echo prints that literally, and the line stopped counting.)
if [[ ${SKIP_COUNT} -gt 0 ]]; then
    echo ""
    echo "Skipped tests:"
    for T in "${SKIP_TESTS[@]}"; do
        echo "  - ${T}"
    done
fi

if [[ ${#RETRIED_TESTS[@]} -gt 0 ]]; then
    echo ""
    echo "⚠️  Retried after a first-attempt failure: ${#RETRIED_TESTS[@]}"
    for T in "${RETRIED_TESTS[@]}"; do
        echo "  - ${T}"
    done
fi

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for T in "${FAIL_TESTS[@]}"; do
        echo "  - ${T}"
    done
    echo ""
    exit 1
fi

echo ""
echo -e "\033[32m  All template tests passed!\033[0m"
echo ""
