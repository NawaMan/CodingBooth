#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Runs all test*.sh scripts in this directory (excluding test-helpers--source.sh)
# Supports parallel execution with --max-parallel flag

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default settings
MAX_PARALLEL=1
VERBOSE=""
TEST_TIMEOUT=600  # 10 minutes per test

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE="--verbose"
            shift
            ;;
        --max-parallel)
            MAX_PARALLEL="$2"
            shift 2
            ;;
        --timeout)
            TEST_TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verbose             Show verbose test output"
            echo "  --max-parallel <n>    Maximum parallel tests (default: 1)"
            echo "  --timeout <seconds>   Timeout per test in seconds (default: 600)"
            echo "  --help, -h            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

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
echo "Running Init Tests"
echo "==============================================================================="
echo "Tests to run: ${#test_files[@]}"
if [[ $MAX_PARALLEL -gt 1 ]]; then
    echo "Max parallel: $MAX_PARALLEL"
fi
echo ""

OVERALL_START=$(date +%s)

if [[ $MAX_PARALLEL -le 1 ]]; then
    # Sequential mode (original behavior)
    TEST_COUNT=0
    PASS_COUNT=0
    FAIL_COUNT=0
    FAIL_TESTS=()

    for test_file in "${test_files[@]}"; do
        name=$(basename "$test_file" .sh)
        TEST_COUNT=$((TEST_COUNT + 1))

        echo "-------------------------------------------------------------------------------"

        if (cd "$SCRIPT_DIR" && timeout "$TEST_TIMEOUT" bash "$test_file" $VERBOSE); then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            exit_code=$?
            FAIL_COUNT=$((FAIL_COUNT + 1))
            if [[ $exit_code -eq 124 ]]; then
                FAIL_TESTS+=("$name (TIMEOUT)")
            else
                FAIL_TESTS+=("$name")
            fi
        fi
        echo ""
    done

    OVERALL_END=$(date +%s)
    OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

    echo "========================================"
    echo "  Init Test Summary"
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

    echo -e "\033[32m  All init tests passed!\033[0m"
    echo ""

else
    # Parallel mode
    RESULTS_DIR=$(mktemp -d)
    trap "rm -rf $RESULTS_DIR" EXIT

    running_jobs=0
    declare -a job_pids=()
    declare -a job_names=()

    for test_file in "${test_files[@]}"; do
        name=$(basename "$test_file" .sh)

        # Wait if we've hit the parallel limit
        while [[ $running_jobs -ge $MAX_PARALLEL ]]; do
            wait -n 2>/dev/null || true
            running_jobs=0
            for pid in "${job_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    running_jobs=$((running_jobs + 1))
                fi
            done
        done

        # Start test in background
        (
            start_time=$(date +%s)

            set +e
            cd "$SCRIPT_DIR" && timeout "$TEST_TIMEOUT" bash "$test_file" $VERBOSE
            test_exit=$?
            set -e

            end_time=$(date +%s)
            duration=$((end_time - start_time))

            echo "$test_exit" > "$RESULTS_DIR/$name.result"
            echo "$duration"  > "$RESULTS_DIR/$name.duration"
        ) > "$SCRIPT_DIR/log--$name.log" 2>&1 &

        job_pids+=($!)
        job_names+=("$name")
        running_jobs=$((running_jobs + 1))

        echo "Started: $name (pid: ${job_pids[-1]})"
    done

    echo ""
    echo "Waiting for all tests to complete..."
    echo ""

    wait

    OVERALL_END=$(date +%s)
    OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

    # Collect results
    TEST_COUNT=0
    PASS_COUNT=0
    FAIL_COUNT=0
    FAIL_TESTS=()

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'

    for name in "${job_names[@]}"; do
        TEST_COUNT=$((TEST_COUNT + 1))

        result_code=1
        if [[ -f "$RESULTS_DIR/$name.result" ]]; then
            result_code=$(cat "$RESULTS_DIR/$name.result")
        fi

        duration=0
        if [[ -f "$RESULTS_DIR/$name.duration" ]]; then
            duration=$(cat "$RESULTS_DIR/$name.duration")
        fi

        if [[ "$result_code" == "0" ]]; then
            PASS_COUNT=$((PASS_COUNT + 1))
            printf "  ${GREEN}%-45s %5ss  PASSED${NC}\n" "$name" "$duration"
        elif [[ "$result_code" == "124" ]]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAIL_TESTS+=("$name (TIMEOUT)")
            printf "  ${RED}%-45s %5ss  TIMEOUT${NC}\n" "$name" "$duration"
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAIL_TESTS+=("$name")
            printf "  ${RED}%-45s %5ss  FAILED${NC}\n" "$name" "$duration"
        fi
    done

    echo ""
    echo "========================================"
    echo "  Init Test Summary"
    echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Failed: ${FAIL_COUNT}"
    echo "  Duration: ${OVERALL_DURATION}s (wall clock)"
    echo "========================================"

    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        echo ""
        echo "Failed tests:"
        for T in "${FAIL_TESTS[@]}"; do
            echo -e "  \u274c ${T}"
        done
        echo ""
        echo "Check log--<testname>.log for details."
        echo ""
        exit 1
    fi

    echo -e "${GREEN}  All init tests passed!${NC}"
    echo ""
fi
