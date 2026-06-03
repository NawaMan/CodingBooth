#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

##=============================================================================================##
## NOTE                                                                                        ##
## Example tests are intermittent when run together, so if some fail, try again individually.  ##
##=============================================================================================##


# Test runner script for workspace examples
# Supports tag filtering and parallel execution

# This script is compatible with macOS's stock Bash 3.2, but prefers a modern
# bash if one is installed (its `wait -n` makes the parallel scheduler slightly
# more efficient). Re-exec under a newer bash when available; otherwise continue.
if (( BASH_VERSINFO[0] < 4 )); then
    for _newer_bash in /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash; do
        if [[ -x "$_newer_bash" ]]; then
            exec "$_newer_bash" "$0" "$@"
        fi
    done
fi

# True when running under bash 4.3+ (has `wait -n`).
HAS_WAIT_N=false
if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
    HAS_WAIT_N=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default settings
MAX_PARALLEL=1

EXAMPLE_TIMEOUT=900  # 15 minutes per example
declare -a FILTER_TAGS=()
declare -a FILTER_EXAMPLES=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            FILTER_TAGS+=("$2")
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
            EXAMPLE_TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --tag <tag>           Filter examples by tag (can be used multiple times, OR logic)"
            echo "  --example <example>   Filter by example name (can be used multiple times, OR logic)"
            echo "                        (tries appending '-example' if exact match not found)"
            echo "  --max-parallel <n>    Maximum parallel examples (default: 32)"
            echo "  --timeout <seconds>   Timeout per example in seconds (default: 600 = 10 min)"
            echo "  --help, -h            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Run all tests"
            echo "  $0 --tag language               # Run tests tagged with 'language'"
            echo "  $0 --tag cloud --tag tool       # Run tests tagged with 'cloud' OR 'tool'"
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
    local tags_file="$example_dir/.cb-tests/tags.txt"

    # If no filter tags specified, match all
    if [ ${#FILTER_TAGS[@]} -eq 0 ]; then
        return 0
    fi

    # Backward compatibility while examples migrate:
    # prefer .cb-tests/tags.txt, fallback to root tags.txt.
    if [ ! -f "$tags_file" ]; then
        tags_file="$example_dir/tags.txt"
    fi

    # If no tags file exists, don't match.
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

# Collect examples
declare -a examples=()

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

    # Check if has any tests (root-level or .cb-tests/)
    test_count=$(find "$example_dir" "$example_dir/.cb-tests" -maxdepth 1 -name "test0*.sh" 2>/dev/null | wc -l)
    if [ "$test_count" -eq 0 ]; then
        continue
    fi

    examples+=("$example_dir")
done

# Check if any tests to run
if [ ${#examples[@]} -eq 0 ]; then
    echo "No matching tests found."
    [ ${#FILTER_TAGS[@]} -gt 0 ] && echo "Filter tags: ${FILTER_TAGS[*]}"
    [ ${#FILTER_EXAMPLES[@]} -gt 0 ] && echo "Filter examples: ${FILTER_EXAMPLES[*]}"
    exit 0
fi

# Pick a timeout command. macOS doesn't ship `timeout`; coreutils provides
# `gtimeout` when installed via Homebrew. Fall back to a Perl shim (preinstalled
# on macOS) that preserves the GNU `timeout` exit-code convention (124 on
# timeout) so the result classifier below still works.
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD=(timeout)
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD=(gtimeout)
elif command -v perl >/dev/null 2>&1; then
    TIMEOUT_CMD=(perl -e '
        my $secs = shift;
        my $pid = fork();
        die "fork: $!" unless defined $pid;
        if ($pid == 0) { exec @ARGV or exit 127; }
        local $SIG{ALRM} = sub {
            kill "TERM", $pid;
            sleep 5;
            kill "KILL", $pid;
            exit 124;
        };
        alarm $secs;
        waitpid($pid, 0);
        exit($? >> 8);
    ' --)
else
    echo "WARNING: no 'timeout', 'gtimeout', or 'perl' found — examples will run without a hang guard." >&2
    TIMEOUT_CMD=()
fi

echo "========================================"
echo "Running Example Tests"
echo "========================================"
echo "Examples to run: ${#examples[@]}"
echo "Max parallel: $MAX_PARALLEL"
[ ${#FILTER_TAGS[@]} -gt 0 ] && echo "Filter tags: ${FILTER_TAGS[*]}"
[ ${#FILTER_EXAMPLES[@]} -gt 0 ] && echo "Filter examples: ${FILTER_EXAMPLES[*]}"
echo ""

# Record overall start time
OVERALL_START=$(date +%s)

# Create temp directory for results
RESULTS_DIR=$(mktemp -d)
trap "rm -rf $RESULTS_DIR" EXIT

# Run examples in parallel with limit
running_jobs=0
declare -a job_pids=()
declare -a job_examples=()

for example_dir in "${examples[@]}"; do
    example_name=$(basename "$example_dir")

    # Wait if we've hit the parallel limit
    while [ $running_jobs -ge $MAX_PARALLEL ]; do
        # Wait for any job to finish. `wait -n` (bash 4.3+) blocks until the next
        # job exits; on bash 3.2 fall back to polling with a short sleep.
        if [ "$HAS_WAIT_N" = true ]; then
            wait -n 2>/dev/null || true
        else
            sleep 1
        fi
        # Recount running jobs
        running_jobs=0
        for pid in "${job_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                running_jobs=$((running_jobs + 1))
            fi
        done
    done

    # Start example in background with timeout
    (
        start_time=$(date +%s)

        test_runner="$example_dir/run-automatic-on-host-test.sh"
        test_count=$(find "$example_dir" "$example_dir/.cb-tests" -maxdepth 1 -name "test0*.sh" 2>/dev/null | wc -l)

        echo "========================================"
        echo "Example: $example_name ($test_count test(s))"
        echo "========================================"

        set +e
        if [[ ${#TIMEOUT_CMD[@]} -gt 0 ]]; then
            "${TIMEOUT_CMD[@]}" "$EXAMPLE_TIMEOUT" bash -c "cd '$example_dir' && VARIANT=base CB_PORT=RANDOM ./run-automatic-on-host-test.sh"
        else
            bash -c "cd '$example_dir' && VARIANT=base CB_PORT=RANDOM ./run-automatic-on-host-test.sh"
        fi
        test_exit_code=$?
        set -e

        end_time=$(date +%s)
        duration=$((end_time - start_time))

        echo "----------------------------------------"
        if [ $test_exit_code -eq 0 ]; then
            echo "✓ $example_name passed (${duration}s)"
            echo "0" > "$RESULTS_DIR/$example_name.result"
        elif [ $test_exit_code -eq 124 ]; then
            echo "⏱ $example_name TIMEOUT (${duration}s)"
            echo "124" > "$RESULTS_DIR/$example_name.result"
        else
            echo "✗ $example_name FAILED (${duration}s)"
            echo "1" > "$RESULTS_DIR/$example_name.result"
        fi
        echo ""

        # Write duration
        echo "$duration" > "$RESULTS_DIR/$example_name.duration"

        # Post-cleanup: ensure containers are fully stopped
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
    ) > "$SCRIPT_DIR/.$example_name.log" 2>&1 &

    last_pid=$!
    job_pids+=("$last_pid")
    job_examples+=("$example_name")
    running_jobs=$((running_jobs + 1))

    echo "Started example: $example_name (pid: $last_pid)"
done

echo ""
echo "Waiting for all examples to complete..."
echo ""

# Wait for all jobs
wait

# Record overall end time
OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

# Result/duration accessors. Data lives in per-example files under RESULTS_DIR,
# so we read on demand instead of caching in associative arrays (bash 4 only).
get_result() {
    local f="$RESULTS_DIR/$1.result"
    [ -f "$f" ] && cat "$f" || echo 1
}
get_duration() {
    local f="$RESULTS_DIR/$1.duration"
    [ -f "$f" ] && cat "$f" || echo 0
}

# Collect results
failed_examples=()
passed_examples=()
timeout_examples=()

for example_dir in "${examples[@]}"; do
    example_name=$(basename "$example_dir")

    result_code=$(get_result "$example_name")

    if [ "$result_code" = "0" ]; then
        passed_examples+=("$example_name")
    elif [ "$result_code" = "124" ]; then
        timeout_examples+=("$example_name")
        failed_examples+=("$example_name")
    else
        failed_examples+=("$example_name")
    fi
done

# Print summary
echo "======================================================"
echo "Test Summary"
echo "======================================================"

num_passed=${#passed_examples[@]}
num_failed=${#failed_examples[@]}
total=$((num_passed + num_failed))

# Colors
RED='\033[0;31m'
NC='\033[0m' # No Color

# Show results table
for example_dir in "${examples[@]}"; do
    example_name=$(basename "$example_dir")
    duration_str=$(format_duration "$(get_duration "$example_name")")
    result_code=$(get_result "$example_name")

    if [ "$result_code" = "0" ]; then
        printf "  %-32s %-12s %s\n" "$example_name" "$duration_str" "passed"
    elif [ "$result_code" = "124" ]; then
        printf "${RED}  %-32s %-12s %s${NC}\n" "$example_name" "$duration_str" "TIMEOUT"
    else
        printf "${RED}  %-32s %-12s %s${NC}\n" "$example_name" "$duration_str" "FAILED"
    fi
done
echo "------------------------------------------------------"
printf "  %-32s %-12s\n" "Total (wall clock):" "$(format_duration $OVERALL_DURATION)"

echo ""
echo "======================================================"
if [ $num_failed -eq 0 ]; then
    echo "✓ All $total example(s) passed!"
else
    printf "${RED}✗ $num_failed out of $total example(s) FAILED${NC}\n"
    echo ""
    echo "Failed examples:"
    for example_name in "${failed_examples[@]}"; do
        result_code=$(get_result "$example_name")
        if [ "$result_code" = "124" ]; then
            printf "${RED}  - %-32s %-12s - TIMEOUT - see .%s.log${NC}\n" "$example_name" "($(format_duration "$(get_duration "$example_name")"))" "$example_name"
        else
            printf "${RED}  - %-32s %-12s - see .%s.log${NC}\n" "$example_name" "($(format_duration "$(get_duration "$example_name")"))" "$example_name"
        fi
    done
    echo ""
    echo "======================================================"
    echo "Example tests are intermittent when run together, "
    echo "so if some tests failed, try running them individually:"
    echo "  ./run-example-tests.sh --example <example_name>"
    echo "======================================================"
fi

exit $([ $num_failed -eq 0 ] && echo 0 || echo 1)
