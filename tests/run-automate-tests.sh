#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Master test runner script
# Runs all test suites sequentially with a live status graph.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

# ── Suite definitions ────────────────────────────────────────────────

SUITES=(unit basic dryrun boothfile complex init)
SUITE_LABELS=("UNIT" "BASIC" "DRYRUN" "BOOTHFILE" "COMPLEX" "INIT")
SUITE_RUNNERS=(
    "./run-all-go-tests.sh"
    "./run-basic-tests.sh"
    "./run-dryrun-tests.sh"
    "./run-boothfile-tests.sh"
    "./run-complex-tests.sh"
    "./run-all-tests.sh"
)

# ── Parse args ───────────────────────────────────────────────────────

ONLY_SUITES=""
SKIP_SUITES=""

usage() {
    cat <<'EOF'
Usage: ./run-automate-tests.sh [options]

Options:
  --only <suites>   Run only the specified suites (comma-separated)
  --skip <suites>   Skip the specified suites (comma-separated)
  -h, --help        Show this help

Available suites: unit, basic, dryrun, boothfile, complex, init

Examples:
  ./run-automate-tests.sh --only dryrun
  ./run-automate-tests.sh --only dryrun,init
  ./run-automate-tests.sh --skip basic,complex
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            ONLY_SUITES="$2"
            shift 2
            ;;
        --skip)
            SKIP_SUITES="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Determine which suites to run
should_run_suite() {
    local suite="$1"
    if [[ -n "$ONLY_SUITES" ]]; then
        # Only run if explicitly listed
        echo ",$ONLY_SUITES," | grep -q ",$suite," && return 0 || return 1
    fi
    if [[ -n "$SKIP_SUITES" ]]; then
        # Skip if explicitly listed
        echo ",$SKIP_SUITES," | grep -q ",$suite," && return 1 || return 0
    fi
    return 0
}

# ── State ────────────────────────────────────────────────────────────

declare -A STATUS
declare -A PASS_COUNTS
declare -A FAIL_COUNTS
declare -A FAILURE_LINES

for s in "${SUITES[@]}"; do
    if should_run_suite "$s"; then
        STATUS[$s]=pending
    else
        STATUS[$s]=skipped
    fi
    PASS_COUNTS[$s]=0
    FAIL_COUNTS[$s]=0
    FAILURE_LINES[$s]=""
done

CURRENT_PID=""
STOP_REQUESTED=false
OVERALL_START=$(date +%s)

# ── ANSI Colors ──────────────────────────────────────────────────────

C_RESET='\033[0m'
C_WHITE='\033[0;37m'
C_GREEN='\033[1;32m'
C_BLUE='\033[1;34m'
C_RED='\033[1;31m'
C_GRAY='\033[0;90m'
C_BOLD='\033[1m'

# ── Helpers ──────────────────────────────────────────────────────────

last_log_line() {
    local log_file="$1" max_len="${2:-55}"
    [[ -f "$log_file" ]] || return
    local line
    line=$(tail -1 "$log_file" 2>/dev/null | tr -d '\r')
    [[ -z "$line" ]] && return
    if (( ${#line} > max_len )); then
        line="${line:0:$max_len}..."
    fi
    echo -n "$line"
}

status_icon() {
    case "$1" in
        pending)   echo -ne "${C_WHITE}◯" ;;
        running)   echo -ne "${C_BLUE}⟳" ;;
        done)      echo -ne "${C_GREEN}✔" ;;
        failed)    echo -ne "${C_RED}✘" ;;
        skipped)   echo -ne "${C_GRAY}○" ;;
        cancelled) echo -ne "${C_GRAY}—" ;;
    esac
}

# Count pass/fail from a log file by looking for common test result markers.
sync_counts() {
    local suite="$1"
    local log="${LOG_DIR}/${suite}.log"
    [[ -f "$log" ]] || return

    # Count passes and failures from test output markers.
    # Strip ANSI escape codes first — test output is colorized.
    local stripped
    stripped=$(sed 's/\x1b\[[0-9;]*m//g' "$log" 2>/dev/null) || stripped=""
    local pass fail
    pass=$(echo "$stripped" | grep -cE '✅|PASSED|^ok ' 2>/dev/null) || pass=0
    fail=$(echo "$stripped" | grep -cE '❌|FAILED|^--- FAIL' 2>/dev/null) || fail=0
    PASS_COUNTS[$suite]=$((pass))
    FAIL_COUNTS[$suite]=$((fail))

    # Collect failure lines (trimmed, max 10)
    local failures
    failures=$(echo "$stripped" | grep -E '❌|FAILED' 2>/dev/null | head -10 | while IFS= read -r line; do
        if (( ${#line} > 70 )); then
            echo "    ${line:0:70}..."
        else
            echo "    ${line}"
        fi
    done) || true
    FAILURE_LINES[$suite]="$failures"
}

# ── Status graph ─────────────────────────────────────────────────────

GRAPH_DRAWN=false
PREV_GRAPH_LINES=0

compute_graph_lines() {
    local lines=0
    for s in "${SUITES[@]}"; do
        lines=$((lines + 1))
        # Count failure lines for this suite
        if [[ -n "${FAILURE_LINES[$s]}" ]]; then
            local n
            n=$(echo "${FAILURE_LINES[$s]}" | wc -l)
            lines=$((lines + n))
        fi
    done
    # +3 for blank + Logs + Hint
    echo $((lines + 3))
}

draw_graph() {
    local new_lines
    new_lines=$(compute_graph_lines)

    if [[ "$GRAPH_DRAWN" == true ]]; then
        printf '\033[%dA' "$PREV_GRAPH_LINES"
    fi

    local s label total
    local PAD=12

    for i in "${!SUITES[@]}"; do
        s="${SUITES[$i]}"
        label="${SUITE_LABELS[$i]}"

        printf "  %-${PAD}s " "$label"
        status_icon "${STATUS[$s]}"

        # Show pass/fail counts if any activity
        local p=${PASS_COUNTS[$s]:-0}
        local f=${FAIL_COUNTS[$s]:-0}
        total=$(( p + f ))
        if (( total > 0 )); then
            if (( f > 0 )); then
                printf " ${C_RED}%d${C_RESET}/${C_GREEN}%d${C_RESET}" "$f" "$total"
            else
                printf " ${C_GREEN}%d${C_RESET}/%d" "$p" "$total"
            fi
        fi

        # Show last log line for running suite
        if [[ "${STATUS[$s]}" == "running" ]]; then
            local progress
            progress=$(last_log_line "${LOG_DIR}/${s}.log")
            if [[ -n "$progress" ]]; then
                printf "  ${C_GRAY}%s${C_RESET}" "$progress"
            fi
        fi

        # Show "skipped" label
        if [[ "${STATUS[$s]}" == "skipped" ]]; then
            printf " ${C_GRAY}skipped${C_RESET}"
        fi

        printf "\033[K${C_RESET}\n"

        # Print failure lines below this suite
        if [[ -n "${FAILURE_LINES[$s]}" ]]; then
            while IFS= read -r fline; do
                printf "${C_RED}%s${C_RESET}\033[K\n" "$fline"
            done <<< "${FAILURE_LINES[$s]}"
        fi
    done

    printf "\033[K\n"
    printf "${C_GRAY}Logs:  ${LOG_DIR}/${C_RESET}\033[K\n"
    printf "${C_GRAY}Hint:  Ctrl+C to stop   Ctrl+Z to leave this run in the background${C_RESET}\033[K\n"

    PREV_GRAPH_LINES=$new_lines
    GRAPH_DRAWN=true
}

# ── Run a suite ──────────────────────────────────────────────────────

run_suite() {
    local suite="$1" dir="$2" runner="$3"
    local log="${LOG_DIR}/${suite}.log"
    local exit_file="${LOG_DIR}/${suite}.exit"

    rm -f "$log" "$exit_file"

    (
        cd "$SCRIPT_DIR/$dir"
        $runner > "$log" 2>&1
        echo $? > "$exit_file"
    ) &
    CURRENT_PID=$!
}

poll_suite() {
    local suite="$1"

    while true; do
        # Check if suite process is still running
        if ! kill -0 "$CURRENT_PID" 2>/dev/null; then
            wait "$CURRENT_PID" 2>/dev/null || true
            break
        fi

        sync_counts "$suite"
        draw_graph

        if [[ "$STOP_REQUESTED" == true ]]; then
            kill "$CURRENT_PID" 2>/dev/null || true
            wait "$CURRENT_PID" 2>/dev/null || true
            break
        fi

        sleep 2
    done

    # Final sync after suite completes
    sync_counts "$suite"
}

# ── Ctrl+C handler ───────────────────────────────────────────────────

handle_sigint() {
    echo ""
    echo -ne "${C_BOLD}Ctrl+C received.${C_RESET} Type ${C_RED}stop${C_RESET} to stop, or press Enter to continue: "
    trap - INT
    local answer=""
    read -r answer || true
    trap handle_sigint INT

    if [[ "$answer" == "stop" ]]; then
        STOP_REQUESTED=true
        if [[ -n "$CURRENT_PID" ]] && kill -0 "$CURRENT_PID" 2>/dev/null; then
            kill "$CURRENT_PID" 2>/dev/null || true
            wait "$CURRENT_PID" 2>/dev/null || true
        fi
        for s in "${SUITES[@]}"; do
            if [[ "${STATUS[$s]}" == "pending" || "${STATUS[$s]}" == "running" ]]; then
                STATUS[$s]=cancelled
            fi
        done
        draw_graph
        echo -e "${C_RED}Tests stopped by user.${C_RESET}"
        exit 1
    fi
}

# ── Main ─────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"
rm -f "${LOG_DIR}"/*.exit

trap handle_sigint INT

echo -e "${C_BOLD}CodingBooth Tests${C_RESET}"
echo ""

draw_graph

for i in "${!SUITES[@]}"; do
    suite="${SUITES[$i]}"
    dir="${SUITES[$i]}"
    runner="${SUITE_RUNNERS[$i]}"

    if [[ "$STOP_REQUESTED" == true ]]; then
        break
    fi

    # Skip suites filtered out by --only/--skip
    if [[ "${STATUS[$suite]}" == "skipped" ]]; then
        continue
    fi

    STATUS[$suite]=running
    draw_graph

    run_suite "$suite" "$dir" "$runner"
    poll_suite "$suite"

    # Read exit code
    exit_file="${LOG_DIR}/${suite}.exit"
    exit_code=1
    if [[ -f "$exit_file" ]]; then
        exit_code=$(cat "$exit_file")
    fi

    # Check for skip (exit 0 but log contains SKIP)
    if [[ "$exit_code" == "0" ]] && grep -q '^SKIP:' "${LOG_DIR}/${suite}.log" 2>/dev/null; then
        STATUS[$suite]=skipped
    elif [[ "$exit_code" == "0" ]]; then
        STATUS[$suite]=done
    else
        STATUS[$suite]=failed
    fi

    draw_graph
done

# Clean up exit files
rm -f "${LOG_DIR}"/*.exit

# ── Summary ──────────────────────────────────────────────────────────

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))

echo ""
echo -e "${C_BOLD}Test Summary${C_RESET}"

has_failure=false
total_pass=0
total_fail=0
for s in "${SUITES[@]}"; do
    total_pass=$((total_pass + ${PASS_COUNTS[$s]:-0}))
    total_fail=$((total_fail + ${FAIL_COUNTS[$s]:-0}))
    if [[ "${STATUS[$s]}" == "failed" ]]; then
        has_failure=true
    fi
done

echo "  Total: $((total_pass + total_fail))   Passed: ${total_pass}   Failed: ${total_fail}   Duration: ${OVERALL_DURATION}s"
echo ""

if [[ "$has_failure" == true ]]; then
    echo -e "${C_RED}Some tests failed. Check logs in ${LOG_DIR}/${C_RESET}"
    exit 1
fi

echo -e "${C_GREEN}All tests passed.${C_RESET}"
