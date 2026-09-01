#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Runs all test*.sh scripts in this directory (excluding test-helpers--source.sh)
# Config-only tests run 4 at a time in parallel (--jobs N).
# Tests that start Docker containers (booth-collect) run sequentially to avoid port conflicts.
# --help for the flags; --verbose shows the image builds, --heartbeat what is still in
# flight, --only <glob> narrows the run to one test or a family.
#
# Two files per test, and they must stay separate: log--<name>.log is the test's own
# detail log (it writes its command trace there and asserts against it), out--<name>.log
# is this runner's capture of the test's console output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Never open the host's browser: a booth that serves a UI does so by default.
# These tests do not source common--source.sh, which sets it everywhere else.
export CB_BROWSER=false

# The transient in-flight line (see progress--source.sh). progress_init returns
# non-zero when there is no terminal to draw on, and the printed heartbeat below
# stays as the signal for that case -- a CI log has nothing else.
source "${SCRIPT_DIR}/../progress--source.sh"
progress_init || true

VERBOSE=""
PARALLEL=4
HEARTBEAT="${CB_TEST_HEARTBEAT:-15}"
declare -a ONLY=()

usage() {
    cat <<'USAGE'
Usage: ./run-all-tests.sh [--verbose] [--only GLOB] [--jobs N] [--heartbeat SECS] [--help]

  --verbose         Pass --verbose to every test: each test echoes the commands it
                    runs, and booth image builds are no longer silenced -- so a run
                    that is sitting on a long build shows what it is building.
  --only GLOB       Run only the tests whose name matches GLOB (e.g. --only 'test8*'
                    or --only test82-project-local-templates-and-recipes). Repeatable.
  --jobs N          Parallel slots for the config-only tests (default 4).
  --heartbeat SECS  How often to report which tests are still in flight
                    (default 15; 0 turns it off). Also settable via CB_TEST_HEARTBEAT.
                    Only used when there is no terminal to draw the live line on.
  --help            Show this message.

Tests that start a container run sequentially and stream live. The rest run in
parallel with their output held back until each finishes, so on a terminal a
single self-erasing line reports what is in flight and for how long -- that line
is what distinguishes a slow image build from a hang. It leaves nothing behind:
results print exactly as they always did. CB_NO_TEST_PROGRESS=1 turns it off, and
without a terminal the run falls back to the printed --heartbeat report.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)      VERBOSE="--verbose" ;;
        --only)         ONLY+=("$2"); shift ;;
        --only=*)       ONLY+=("${1#*=}") ;;
        --jobs)         PARALLEL="$2"; shift ;;
        --jobs=*)       PARALLEL="${1#*=}" ;;
        --heartbeat)    HEARTBEAT="$2"; shift ;;
        --heartbeat=*)  HEARTBEAT="${1#*=}" ;;
        --help|-h)      usage; exit 0 ;;
        *)              echo "Unknown option: $1" >&2; echo "" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || (( PARALLEL < 1 )); then
    echo "--jobs must be a positive integer (got '${PARALLEL}')" >&2
    exit 2
fi
if ! [[ "$HEARTBEAT" =~ ^[0-9]+$ ]]; then
    echo "--heartbeat must be a non-negative integer (got '${HEARTBEAT}')" >&2
    exit 2
fi

# Collect and classify test files
declare -a seq_tests=()   # booth-collect tests (need Docker port) → sequential
declare -a par_tests=()   # config-only tests → parallel

# Does this test name match one of the --only globs? No globs means everything runs.
selected() {
    (( ${#ONLY[@]} == 0 )) && return 0
    local pattern
    for pattern in "${ONLY[@]}"; do
        # shellcheck disable=SC2053 -- an unquoted right side is the glob match
        [[ "$1" == $pattern ]] && return 0
    done
    return 1
}

for test_file in "$SCRIPT_DIR"/test*.sh; do
    name=$(basename "$test_file" .sh)
    [[ "$name" == "test-helpers--source" ]] && continue
    selected "$name" || continue
    if grep -q 'booth-collect' "$test_file" 2>/dev/null; then
        seq_tests+=("$test_file")
    else
        par_tests+=("$test_file")
    fi
done

TOTAL=$(( ${#seq_tests[@]} + ${#par_tests[@]} ))

if [[ $TOTAL -eq 0 ]]; then
    if (( ${#ONLY[@]} > 0 )); then
        echo "No test matches --only ${ONLY[*]}" >&2
        exit 2
    fi
    echo "No test files found."
    exit 0
fi

echo "==============================================================================="
echo "Running Config Tests"
echo "==============================================================================="
echo "Tests to run: ${TOTAL} (${#seq_tests[@]} sequential, ${#par_tests[@]} parallel)"
echo ""

OVERALL_START=$(date +%s)

PASS_COUNT=0
FAIL_COUNT=0
FAIL_TESTS=()

# Retried tests are collected in a file rather than an array: the parallel path
# runs each test in a background subshell, and an array there would not survive.
RETRIED_LIST="$(mktemp)"
trap 'rm -f "$RETRIED_LIST"' EXIT

# ── Sequential tests (booth-collect: uses Docker ports) ─────────────

for test_file in "${seq_tests[@]}"; do
    name=$(basename "$test_file" .sh)
    echo "-------------------------------------------------------------------------------"

    seq_start=$(date +%s)
    seq_rc=0
    (cd "$SCRIPT_DIR" && bash "$test_file" $VERBOSE) || seq_rc=$?
    if (( seq_rc == 0 )); then
        PASS_COUNT=$((PASS_COUNT + 1))
    elif (( seq_rc == 2 )); then
        # `skip` — a missing prerequisite, not something a retry would fix.
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("$name")
    else
        echo "⚠️  FAILED: ${name} — retrying once"
        printf '%s\n' "$name" >> "$RETRIED_LIST"
        if (cd "$SCRIPT_DIR" && bash "$test_file" $VERBOSE); then
            echo "✅ PASSED after retry: ${name}"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAIL_TESTS+=("$name")
        fi
    fi
    echo "   (${name}: $(( $(date +%s) - seq_start ))s)"
    echo ""
done

# ── Parallel tests (config-only: no Docker ports) ───────────────────

# Where a parallel test's console output is captured.
#
# Deliberately NOT log--<name>.log: that file belongs to the test itself, which
# writes its command trace there and, on a --verbose failure, cats it back out for
# the operator. Capturing stdout into the same file made that `cat "$log"` read what
# it had just written -- `cat file >> file` never reaches EOF. One --verbose run of a
# failing test grew a 362GB log that way and killed bash with an xrealloc overflow.
# Two writers on one file also interleaved by byte offset, which is why finished
# tests printed spliced-together garbage.
capture_file() {
    echo "${SCRIPT_DIR}/out--$(basename "$1" .sh).log"
}

# Run a single test, capturing its console output.
# CB_NO_BUILD_PROGRESS: a booth build inside a parallel test would draw its own
# status line on the same terminal this runner is drawing on, and two writers on
# one line is garbage. The runner owns the line here; the test's build output
# still goes to its capture file, and the line reports it via progress_tail.
run_one() {
    local test_file="$1"
    local out
    out=$(capture_file "$test_file")

    local rc=0
    (cd "$SCRIPT_DIR" && CB_NO_BUILD_PROGRESS=1 bash "$test_file" $VERBOSE) > "$out" 2>&1 || rc=$?

    # 2 is `skip` from test-helpers--source.sh — a missing prerequisite, which a
    # second attempt cannot change. Only a real failure is worth retrying. (The
    # recorded code stays 0/1 exactly as before; classifying skips is a separate
    # question this change does not touch.)
    if (( rc == 0 )); then
        echo 0 > "${out}.exit"
        return
    fi
    if (( rc == 2 )); then
        echo 1 > "${out}.exit"
        return
    fi

    # Retry once, immediately. The retry is unconditional rather than gated on
    # recognising a transient: tests run the booth with --silence-build, so an
    # archive 503 never reaches this runner as text it could match on.
    #
    # This runs in a background subshell, so the fact of a retry is recorded in a
    # file — an array assignment here would not survive back to the parent.
    echo "" >> "$out"
    echo "⚠️  First attempt failed — retrying once." >> "$out"
    printf '%s\n' "$(basename "$test_file" .sh)" >> "$RETRIED_LIST"

    if (cd "$SCRIPT_DIR" && CB_NO_BUILD_PROGRESS=1 bash "$test_file" $VERBOSE) >> "$out" 2>&1; then
        echo 0 > "${out}.exit"
    else
        echo 1 > "${out}.exit"
    fi
}

# Print results for a completed test. Returns the test's exit code.
print_result() {
    local test_file="$1"
    local started="$2"
    local name out
    name=$(basename "$test_file" .sh)
    out=$(capture_file "$test_file")

    progress_clear
    echo "-------------------------------------------------------------------------------"
    if [[ -f "$out" ]]; then
        cat "$out"
    fi

    local exit_code=0
    if [[ -f "${out}.exit" ]]; then
        exit_code=$(cat "${out}.exit")
        rm -f "${out}.exit"
    fi
    echo "   (${name}: $(( $(date +%s) - started ))s)"
    echo ""
    return "$exit_code"
}

# Report which tests are still in flight, and how long they have been going.
#
# A parallel test's output is held back until it finishes, so between "Begin X" and
# X's results the run prints nothing at all -- a five-minute image build and a hang
# look identical. That ambiguity is what turns a slow run into a Ctrl+C. With
# --verbose the last line of each running test's log comes too, which is the command
# it is actually sitting on.
report_in_flight() {
    local now line="" s name
    now=$(date +%s)
    for (( s=0; s<${#slot_pids[@]}; s++ )); do
        [[ -z "${slot_pids[$s]}" ]] && continue
        name=$(basename "${slot_files[$s]}" .sh)
        line+="${name} $(( now - ${slot_start[$s]} ))s   "
    done
    [[ -z "$line" ]] && return 0

    echo "   ... still running: ${line}"
    [[ -z "$VERBOSE" ]] && return 0

    local out last
    for (( s=0; s<${#slot_pids[@]}; s++ )); do
        [[ -z "${slot_pids[$s]}" ]] && continue
        name=$(basename "${slot_files[$s]}" .sh)
        out=$(capture_file "${slot_files[$s]}")
        # Bounded on purpose: read the last few KB, not the file. `tail -n 1` on a
        # runaway log hands a multi-gigabyte "line" to a command substitution, and
        # bash dies growing the buffer -- a progress report must not be able to kill
        # the run it is reporting on.
        last=$(tail -c 4096 "$out" 2>/dev/null | tail -n 1 | tr -d '\r' | cut -c1-140)
        [[ -n "$last" ]] && echo "       ${name} | ${last}"
    done
}

# The same facts as report_in_flight, on one line that erases itself: which tests
# are in flight and for how long. Drawn from the polling loop below, so the clock
# moves five times a second and nothing here races with the runner's own output.
#
# Under --verbose it carries the last log line of the longest-running test too --
# the command that test is actually sitting on. That costs a `tail`, so it is
# refreshed once a second rather than every frame.
_VERBOSE_DETAIL=""
_VERBOSE_DETAIL_AT=-1

draw_in_flight() {
    [ "$PROGRESS_ACTIVE" = true ] || return 0

    local now line="" s el count=0 oldest="" oldest_start=0
    now=$(date +%s)

    for (( s=0; s<${#slot_pids[@]}; s++ )); do
        [[ -z "${slot_pids[$s]}" ]] && continue
        count=$(( count + 1 ))
        progress_elapsed_var el "${slot_start[$s]}" "$now"
        line+="${slot_names[$s]} ${el} · "
        if (( oldest_start == 0 || slot_start[$s] < oldest_start )); then
            oldest_start=${slot_start[$s]}
            oldest="${slot_files[$s]}"
        fi
    done

    (( count == 0 )) && return 0
    line="${count} in flight · ${line% · }"

    if [[ -n "$VERBOSE" && -n "$oldest" ]]; then
        if (( SECONDS != _VERBOSE_DETAIL_AT )); then
            _VERBOSE_DETAIL=$(progress_tail "$(capture_file "$oldest")" 90)
            _VERBOSE_DETAIL_AT=$SECONDS
        fi
        [[ -n "$_VERBOSE_DETAIL" ]] && line+="  — ${_VERBOSE_DETAIL}"
    fi

    progress_draw "$line"
}

# Track running slots
declare -a slot_pids=()
declare -a slot_files=()
declare -a slot_start=()
declare -a slot_names=()
qi=0

# Fill initial slots
for (( s=0; s<PARALLEL && qi<${#par_tests[@]}; s++, qi++ )); do
    name=$(basename "${par_tests[$qi]}" .sh)
    progress_clear
    echo "Begin $name"
    run_one "${par_tests[$qi]}" &
    slot_pids[$s]=$!
    slot_files[$s]="${par_tests[$qi]}"
    slot_start[$s]=$(date +%s)
    slot_names[$s]="$name"
done

# Process completed tests and refill slots
DONE=0
LAST_BEAT=$(date +%s)
while (( DONE < ${#par_tests[@]} )); do
    for (( s=0; s<${#slot_pids[@]}; s++ )); do
        pid=${slot_pids[$s]}
        [[ -z "$pid" ]] && continue

        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null
            DONE=$((DONE + 1))

            if print_result "${slot_files[$s]}" "${slot_start[$s]}"; then
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
                FAIL_TESTS+=("$(basename "${slot_files[$s]}" .sh)")
            fi
            LAST_BEAT=$(date +%s)   # results just printed; no need to repeat them

            # Refill slot
            if (( qi < ${#par_tests[@]} )); then
                name=$(basename "${par_tests[$qi]}" .sh)
                echo "Begin $name"
                run_one "${par_tests[$qi]}" &
                slot_pids[$s]=$!
                slot_files[$s]="${par_tests[$qi]}"
                slot_start[$s]=$(date +%s)
                slot_names[$s]="$name"
                qi=$((qi + 1))
            else
                slot_pids[$s]=""
                slot_files[$s]=""
                slot_names[$s]=""
            fi
        fi
    done

    if [[ "$PROGRESS_ACTIVE" == true ]]; then
        draw_in_flight
    elif (( HEARTBEAT > 0 )); then
        NOW=$(date +%s)
        if (( NOW - LAST_BEAT >= HEARTBEAT )); then
            report_in_flight
            LAST_BEAT=$NOW
        fi
    fi

    sleep 0.2
done

# ── Summary ─────────────────────────────────────────────────────────

progress_clear

OVERALL_END=$(date +%s)
OVERALL_DURATION=$((OVERALL_END - OVERALL_START))
TEST_COUNT=$((PASS_COUNT + FAIL_COUNT))

echo "========================================"
echo "  Config Test Summary"
echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Failed: ${FAIL_COUNT}"
# A pass that needed a second attempt is still a flake. Report it, or retrying
# quietly converts a real intermittent fault into a green suite.
if [[ -s "$RETRIED_LIST" ]]; then
    echo "  ⚠️  Retried after a first-attempt failure: $(wc -l < "$RETRIED_LIST" | tr -d ' ')"
    sed 's/^/    - /' "$RETRIED_LIST"
fi
echo "  Duration: ${OVERALL_DURATION}s (sequential=${#seq_tests[@]}, parallel=${#par_tests[@]}x${PARALLEL})"
echo "========================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for T in "${FAIL_TESTS[@]}"; do
        echo "  ❌ ${T}"
    done
    echo ""
    exit 1
fi

echo -e "\033[32m  All config tests passed!\033[0m"
echo ""
