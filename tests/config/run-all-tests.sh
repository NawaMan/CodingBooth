#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Runs all test*.sh scripts in this directory (excluding test-helpers--source.sh)
# Config-only tests run 4 at a time in parallel.
# Tests that start Docker containers (booth-collect) run sequentially to avoid port conflicts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Never open the host's browser: a booth that serves a UI does so by default.
# These tests do not source common--source.sh, which sets it everywhere else.
export CB_BROWSER=false

VERBOSE=""
for arg in "$@"; do case "$arg" in --verbose) VERBOSE="--verbose" ;; esac; done

# Collect and classify test files
declare -a seq_tests=()   # booth-collect tests (need Docker port) → sequential
declare -a par_tests=()   # config-only tests → parallel

for test_file in "$SCRIPT_DIR"/test*.sh; do
    name=$(basename "$test_file" .sh)
    [[ "$name" == "test-helpers--source" ]] && continue
    if grep -q 'booth-collect' "$test_file" 2>/dev/null; then
        seq_tests+=("$test_file")
    else
        par_tests+=("$test_file")
    fi
done

TOTAL=$(( ${#seq_tests[@]} + ${#par_tests[@]} ))

if [[ $TOTAL -eq 0 ]]; then
    echo "No test files found."
    exit 0
fi

echo "==============================================================================="
echo "Running Config Tests"
echo "==============================================================================="
echo "Tests to run: ${TOTAL} (${#seq_tests[@]} sequential, ${#par_tests[@]} parallel)"
echo ""

PARALLEL=4
OVERALL_START=$(date +%s)

PASS_COUNT=0
FAIL_COUNT=0
FAIL_TESTS=()

# ── Sequential tests (booth-collect: uses Docker ports) ─────────────

for test_file in "${seq_tests[@]}"; do
    name=$(basename "$test_file" .sh)
    echo "-------------------------------------------------------------------------------"

    if (cd "$SCRIPT_DIR" && bash "$test_file" $VERBOSE); then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("$name")
    fi
    echo ""
done

# ── Parallel tests (config-only: no Docker ports) ───────────────────

# Run a single test, capturing output to its log file.
run_one() {
    local test_file="$1"
    local name
    name=$(basename "$test_file" .sh)
    local log="${SCRIPT_DIR}/log--${name}.log"

    if (cd "$SCRIPT_DIR" && bash "$test_file" $VERBOSE) > "$log" 2>&1; then
        echo 0 > "${log}.exit"
    else
        echo 1 > "${log}.exit"
    fi
}

# Print results for a completed test. Returns the test's exit code.
print_result() {
    local test_file="$1"
    local name
    name=$(basename "$test_file" .sh)
    local log="${SCRIPT_DIR}/log--${name}.log"

    echo "-------------------------------------------------------------------------------"
    if [[ -f "$log" ]]; then
        cat "$log"
    fi

    local exit_code=0
    if [[ -f "${log}.exit" ]]; then
        exit_code=$(cat "${log}.exit")
        rm -f "${log}.exit"
    fi
    echo ""
    return "$exit_code"
}

# Track running slots
declare -a slot_pids=()
declare -a slot_files=()
qi=0

# Fill initial slots
for (( s=0; s<PARALLEL && qi<${#par_tests[@]}; s++, qi++ )); do
    name=$(basename "${par_tests[$qi]}" .sh)
    echo "Begin $name"
    run_one "${par_tests[$qi]}" &
    slot_pids[$s]=$!
    slot_files[$s]="${par_tests[$qi]}"
done

# Process completed tests and refill slots
DONE=0
while (( DONE < ${#par_tests[@]} )); do
    for (( s=0; s<${#slot_pids[@]}; s++ )); do
        pid=${slot_pids[$s]}
        [[ -z "$pid" ]] && continue

        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null
            DONE=$((DONE + 1))

            if print_result "${slot_files[$s]}"; then
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
                FAIL_TESTS+=("$(basename "${slot_files[$s]}" .sh)")
            fi

            # Refill slot
            if (( qi < ${#par_tests[@]} )); then
                name=$(basename "${par_tests[$qi]}" .sh)
                echo "Begin $name"
                run_one "${par_tests[$qi]}" &
                slot_pids[$s]=$!
                slot_files[$s]="${par_tests[$qi]}"
                qi=$((qi + 1))
            else
                slot_pids[$s]=""
                slot_files[$s]=""
            fi
        fi
    done
    sleep 0.2
done

# ── Summary ─────────────────────────────────────────────────────────

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))
TEST_COUNT=$((PASS_COUNT + FAIL_COUNT))

echo "========================================"
echo "  Config Test Summary"
echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Failed: ${FAIL_COUNT}"
echo "  Duration: ${OVERALL_DURATION}s (sequential=${#seq_tests[@]}, parallel=${#par_tests[@]}x${PARALLEL})"
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
