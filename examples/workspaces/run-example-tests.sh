#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Test runner script for workspace examples
# Supports tag filtering and parallel execution by group

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default settings
MAX_PARALLEL=1
GROUP_TIMEOUT=600  # 10 minutes per group
declare -a FILTER_TAGS=()
declare -a FILTER_GROUPS=()
declare -a FILTER_EXAMPLES=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            FILTER_TAGS+=("$2")
            shift 2
            ;;
        --group)
            FILTER_GROUPS+=("$2")
            shift 2
            ;;
        --example)
            FILTER_EXAMPLES+=("$2")
            shift 2
            ;;
        --max-parallel)
            MAX_PARALLEL="$2"
            shift 2
            ;;
        --timeout)
            GROUP_TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --tag <tag>           Filter examples by tag (can be used multiple times, OR logic)"
            echo "  --group <group>       Filter by group name (can be used multiple times, OR logic)"
            echo "  --example <example>   Filter by example name (can be used multiple times, OR logic)"
            echo "                        (tries appending '-example' if exact match not found)"
            echo "  --max-parallel <n>    Maximum parallel groups (default: 4)"
            echo "  --timeout <seconds>   Timeout per group in seconds (default: 300 = 5 min)"
            echo "  --help, -h            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Run all tests"
            echo "  $0 --tag language               # Run tests tagged with 'language'"
            echo "  $0 --tag cloud --tag tool       # Run tests tagged with 'cloud' OR 'tool'"
            echo "  $0 --group go-example           # Run only the go-example group"
            echo "  $0 --example rust               # Run only rust-example (appends -example)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to format duration
format_duration() {
    local seconds=$1
    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    elif [ $seconds -lt 3600 ]; then
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${mins}m ${secs}s"
    else
        local hours=$((seconds / 3600))
        local mins=$(((seconds % 3600) / 60))
        local secs=$((seconds % 60))
        echo "${hours}h ${mins}m ${secs}s"
    fi
}

# Function to check if example matches any filter tag
matches_tag_filter() {
    local example_dir="$1"
    local tags_file="$example_dir/tags.txt"

    # If no filter tags specified, match all
    if [ ${#FILTER_TAGS[@]} -eq 0 ]; then
        return 0
    fi

    # If no tags file exists, don't match
    if [ ! -f "$tags_file" ]; then
        return 1
    fi

    # Check if any filter tag matches (OR logic)
    for filter_tag in "${FILTER_TAGS[@]}"; do
        if grep -qx "$filter_tag" "$tags_file" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

# Function to check if example matches example filter
matches_example_filter() {
    local example_name="$1"

    # If no filter specified, match all
    if [ ${#FILTER_EXAMPLES[@]} -eq 0 ]; then
        return 0
    fi

    # Check if any filter matches (OR logic)
    # Try exact match first, then try with '-example' suffix
    for filter in "${FILTER_EXAMPLES[@]}"; do
        if [ "$example_name" = "$filter" ]; then
            return 0
        fi
        if [ "$example_name" = "${filter}-example" ]; then
            return 0
        fi
    done

    return 1
}

# Function to check if group matches group filter
matches_group_filter() {
    local group_name="$1"

    # If no filter specified, match all
    if [ ${#FILTER_GROUPS[@]} -eq 0 ]; then
        return 0
    fi

    # Check if any filter matches (OR logic)
    for filter in "${FILTER_GROUPS[@]}"; do
        if [ "$group_name" = "$filter" ]; then
            return 0
        fi
    done

    return 1
}

# Function to get group name for an example
get_group() {
    local example_dir="$1"
    local group_file="$example_dir/group.txt"

    if [ -f "$group_file" ]; then
        head -n1 "$group_file" | tr -d '[:space:]'
    else
        basename "$example_dir"
    fi
}

# Function to run tests for a single example (called within a group)
run_example_tests() {
    local example_dir="$1"
    local example_name=$(basename "$example_dir")
    local test_runner="$example_dir/run-automatic-on-host-test.sh"

    # Skip if no test runner exists
    if [ ! -f "$test_runner" ]; then
        return 0
    fi

    # Check if there are any test0*.sh files
    local test_count=$(find "$example_dir" -maxdepth 1 -name "test0*.sh" 2>/dev/null | wc -l)
    if [ "$test_count" -eq 0 ]; then
        echo "  Skipped $example_name (no tests)"
        return 0
    fi

    echo "  Running $example_name ($test_count test(s))..."
    if (cd "$example_dir" && ./run-automatic-on-host-test.sh); then
        echo "  ✓ $example_name passed"
        return 0
    else
        echo "  ✗ $example_name FAILED"
        return 1
    fi
}

# Function to run all tests for a group
run_group() {
    local group_name="$1"
    local results_dir="$2"
    shift 2
    local example_dirs=("$@")

    local group_failed=0
    local group_passed=0

    # Record start time
    local start_time=$(date +%s)

    echo "========================================"
    echo "Group: $group_name"
    echo "========================================"

    for example_dir in "${example_dirs[@]}"; do
        if run_example_tests "$example_dir"; then
            group_passed=$((group_passed + 1))
        else
            group_failed=$((group_failed + 1))
        fi
    done

    # Record end time and calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo "----------------------------------------"
    echo "Group $group_name: $group_passed passed, $group_failed failed ($(format_duration $duration))"
    echo ""

    # Save duration to results
    echo "$duration" > "$results_dir/$group_name.duration"

    if [ $group_failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# Collect examples and organize by group
declare -A groups
declare -a group_order=()

for example_dir in "$SCRIPT_DIR"/*/; do
    example_name=$(basename "$example_dir")

    # Skip non-directories and special files
    [ ! -d "$example_dir" ] && continue

    # Check if matches example filter
    if ! matches_example_filter "$example_name"; then
        continue
    fi

    # Check if matches tag filter
    if ! matches_tag_filter "$example_dir"; then
        continue
    fi

    # Check if has test runner
    test_runner="$example_dir/run-automatic-on-host-test.sh"
    if [ ! -f "$test_runner" ]; then
        continue
    fi

    # Check if has any tests
    test_count=$(find "$example_dir" -maxdepth 1 -name "test0*.sh" 2>/dev/null | wc -l)
    if [ "$test_count" -eq 0 ]; then
        continue
    fi

    group=$(get_group "$example_dir")

    # Check if matches group filter
    if ! matches_group_filter "$group"; then
        continue
    fi

    # Track group order for consistent output
    if [ -z "${groups[$group]}" ]; then
        group_order+=("$group")
    fi

    # Append to group (space-separated)
    if [ -z "${groups[$group]}" ]; then
        groups[$group]="$example_dir"
    else
        groups[$group]="${groups[$group]} $example_dir"
    fi
done

# Check if any tests to run
if [ ${#group_order[@]} -eq 0 ]; then
    echo "No matching tests found."
    [ ${#FILTER_TAGS[@]} -gt 0 ] && echo "Filter tags: ${FILTER_TAGS[*]}"
    [ ${#FILTER_GROUPS[@]} -gt 0 ] && echo "Filter groups: ${FILTER_GROUPS[*]}"
    [ ${#FILTER_EXAMPLES[@]} -gt 0 ] && echo "Filter examples: ${FILTER_EXAMPLES[*]}"
    exit 0
fi

echo "========================================"
echo "Running Example Tests"
echo "========================================"
echo "Groups to run: ${#group_order[@]}"
echo "Max parallel: $MAX_PARALLEL"
[ ${#FILTER_TAGS[@]} -gt 0 ] && echo "Filter tags: ${FILTER_TAGS[*]}"
[ ${#FILTER_GROUPS[@]} -gt 0 ] && echo "Filter groups: ${FILTER_GROUPS[*]}"
[ ${#FILTER_EXAMPLES[@]} -gt 0 ] && echo "Filter examples: ${FILTER_EXAMPLES[*]}"
echo ""

# Record overall start time
OVERALL_START=$(date +%s)

# Create temp directory for results
RESULTS_DIR=$(mktemp -d)
trap "rm -rf $RESULTS_DIR" EXIT

# Run groups in parallel with limit
running_jobs=0
declare -a job_pids=()
declare -a job_groups=()

for group in "${group_order[@]}"; do
    # Wait if we've hit the parallel limit
    while [ $running_jobs -ge $MAX_PARALLEL ]; do
        # Wait for any job to finish
        wait -n 2>/dev/null || true
        # Recount running jobs
        running_jobs=0
        for pid in "${job_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                running_jobs=$((running_jobs + 1))
            fi
        done
    done

    # Get example dirs for this group
    IFS=' ' read -ra example_dirs <<< "${groups[$group]}"

    # Start group in background with timeout per test
    (
        start_time=$(date +%s)

        echo "========================================"
        echo "Group: $group"
        echo "========================================"

        group_failed=0
        group_passed=0

        for example_dir in "${example_dirs[@]}"; do
            example_name=$(basename "$example_dir")
            test_runner="$example_dir/run-automatic-on-host-test.sh"

            if [ ! -f "$test_runner" ]; then
                continue
            fi

            test_count=$(find "$example_dir" -maxdepth 1 -name "test0*.sh" 2>/dev/null | wc -l)
            if [ "$test_count" -eq 0 ]; then
                echo "  Skipped $example_name (no tests)"
                continue
            fi

            echo "  Running $example_name ($test_count test(s))..."
            set +e
            timeout "$GROUP_TIMEOUT" bash -c "cd '$example_dir' && VARIANT=base CB_PORT=RANDOM ./run-automatic-on-host-test.sh"
            test_exit_code=$?
            set -e

            if [ $test_exit_code -eq 0 ]; then
                echo "  ✓ $example_name passed"
                group_passed=$((group_passed + 1))
            elif [ $test_exit_code -eq 124 ]; then
                echo "  ⏱ $example_name TIMEOUT"
                group_failed=$((group_failed + 1))
            else
                echo "  ✗ $example_name FAILED"
                group_failed=$((group_failed + 1))
            fi

            # Post-cleanup: ensure containers are fully stopped before next test
            docker stop "$example_name" 2>/dev/null || true
            docker rm -f "$example_name" 2>/dev/null || true
            # Also cleanup any DinD sidecars
            for container in $(docker ps -aq --filter "name=${example_name}-.*-dind" 2>/dev/null); do
                docker stop "$container" 2>/dev/null || true
                docker rm -f "$container" 2>/dev/null || true
            done
            for network in $(docker network ls --filter "name=${example_name}-" --format '{{.Name}}' 2>/dev/null | grep -- '-net$'); do
                docker network rm "$network" 2>/dev/null || true
            done
            sleep 1
        done

        end_time=$(date +%s)
        duration=$((end_time - start_time))

        echo "----------------------------------------"
        echo "Group $group: $group_passed passed, $group_failed failed (${duration}s)"
        echo ""

        # Write results
        echo "$duration" > "$RESULTS_DIR/$group.duration"
        [ $group_failed -gt 0 ] && echo "1" > "$RESULTS_DIR/$group.result" || echo "0" > "$RESULTS_DIR/$group.result"
    ) > "$SCRIPT_DIR/.$group.log" 2>&1 &

    job_pids+=($!)
    job_groups+=("$group")
    running_jobs=$((running_jobs + 1))

    echo "Started group: $group (pid: ${job_pids[-1]})"
done

echo ""
echo "Waiting for all groups to complete..."
echo ""

# Wait for all jobs
wait

# Record overall end time
OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

# Collect results
failed_groups=()
passed_groups=()
timeout_groups=()
declare -A group_durations
declare -A group_results

for group in "${group_order[@]}"; do
    # Get result
    result_file="$RESULTS_DIR/$group.result"
    result_code=1
    if [ -f "$result_file" ]; then
        result_code=$(cat "$result_file")
    fi
    group_results[$group]=$result_code

    if [ "$result_code" = "0" ]; then
        passed_groups+=("$group")
    elif [ "$result_code" = "124" ]; then
        timeout_groups+=("$group")
        failed_groups+=("$group")
    else
        failed_groups+=("$group")
    fi

    # Get duration
    duration_file="$RESULTS_DIR/$group.duration"
    if [ -f "$duration_file" ]; then
        group_durations[$group]=$(cat "$duration_file")
    else
        group_durations[$group]=0
    fi
done

# Print summary
echo "======================================================"
echo "Test Summary"
echo "======================================================"

num_passed=${#passed_groups[@]}
num_failed=${#failed_groups[@]}
total=$((num_passed + num_failed))

# Colors
RED='\033[0;31m'
NC='\033[0m' # No Color

# Show results table
for group in "${group_order[@]}"; do
    duration_str=$(format_duration ${group_durations[$group]})
    result_code=${group_results[$group]}

    if [ "$result_code" = "0" ]; then
        printf "  %-25s %-12s %s\n" "$group" "$duration_str" "passed"
    elif [ "$result_code" = "124" ]; then
        printf "${RED}  %-25s %-12s %s${NC}\n" "$group" "$duration_str" "TIMEOUT"
    else
        printf "${RED}  %-25s %-12s %s${NC}\n" "$group" "$duration_str" "FAILED"
    fi
done
echo "------------------------------------------------------"
printf "  %-25s %-12s\n" "Total (wall clock):" "$(format_duration $OVERALL_DURATION)"

echo ""
echo "======================================================"
if [ $num_failed -eq 0 ]; then
    echo "✓ All $total group(s) passed!"
else
    printf "${RED}✗ $num_failed out of $total group(s) FAILED${NC}\n"
    echo ""
    echo "Failed groups:"
    for group in "${failed_groups[@]}"; do
        result_code=${group_results[$group]}
        if [ "$result_code" = "124" ]; then
            printf "${RED}  - %-20s %-12s - TIMEOUT - see .%s.log${NC}\n" "$group" "($(format_duration ${group_durations[$group]}))" "$group"
        else
            printf "${RED}  - %-20s %-12s - see .%s.log${NC}\n" "$group" "($(format_duration ${group_durations[$group]}))" "$group"
        fi
    done
fi

exit $([ $num_failed -eq 0 ] && echo 0 || echo 1)
