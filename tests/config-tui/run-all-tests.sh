#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Runs all config-tui test*.sh scripts (VHS-driven TUI tests).
#
# Each test launches the interactive `booth config` TUI under VHS, drives it
# with keystrokes, and asserts on the generated .booth/ files and captured
# terminal frame. VHS spawns ttyd + a headless browser per run, so tests run
# sequentially by default (set PARALLEL>1 to overlap, but expect heavier load).
#
# If the VHS toolchain (vhs/ttyd/ffmpeg) or the codingbooth binary is missing,
# the whole suite reports SKIP and exits 0 so it never breaks CI environments
# that lack VHS.
#
# On a terminal, the test currently recording is reported on a single self-erasing
# line; CB_NO_TEST_PROGRESS=1 turns that off, and without a terminal nothing is
# drawn at all.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Never open the host's browser: a booth that serves a UI does so by default.
# These tests do not source common--source.sh, which sets it everywhere else.
export CB_BROWSER=false

# A VHS run spawns ttyd and a headless browser, records, then encodes -- tens of
# seconds during which this runner has nothing to print. The transient line (see
# progress--source.sh) is what tells the operator which test that is and how long
# it has been going. It draws only on a terminal and leaves nothing behind.
source "${SCRIPT_DIR}/../progress--source.sh"
progress_init || true

VERBOSE=""
PARALLEL="${PARALLEL:-1}"
for arg in "$@"; do
    case "$arg" in
        --verbose) VERBOSE="--verbose" ;;
        --parallel=*) PARALLEL="${arg#*=}" ;;
    esac
done

# ── Availability guard (front-loaded) ───────────────────────────────
missing=()
for tool in vhs ttyd ffmpeg; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
# Find a built codingbooth binary by walking up from here.
have_binary=false
dir="$SCRIPT_DIR"
while [[ "$dir" != "/" ]]; do
    if [[ -x "$dir/codingbooth" && -d "$dir/templates" ]]; then have_binary=true; break; fi
    dir="$(dirname "$dir")"
done
$have_binary || missing+=("codingbooth-binary")

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "==============================================================================="
    echo "Config-TUI Tests"
    echo "==============================================================================="
    echo "SKIP: config-tui suite — missing: ${missing[*]}"
    echo "  These VHS-driven TUI tests require charmbracelet/vhs plus ttyd and ffmpeg,"
    echo "  and a built ./codingbooth binary (build/cli-build.sh)."
    exit 0
fi

# ── Collect tests ───────────────────────────────────────────────────
declare -a tests=()
for test_file in "$SCRIPT_DIR"/test*.sh; do
    name=$(basename "$test_file" .sh)
    [[ "$name" == "tui-helpers--source" ]] && continue
    tests+=("$test_file")
done

TOTAL=${#tests[@]}
if [[ $TOTAL -eq 0 ]]; then
    echo "No test files found."
    exit 0
fi

echo "==============================================================================="
echo "Running Config-TUI Tests (VHS)"
echo "==============================================================================="
echo "Tests to run: ${TOTAL} (parallelism: ${PARALLEL})"
echo ""

OVERALL_START=$(date +%s)
PASS_COUNT=0
FAIL_COUNT=0
FAIL_TESTS=()

# Retried tests are collected in a file rather than an array: run_one executes in
# a background subshell, where an array would not survive.
RETRIED_LIST="$(mktemp)"
trap 'rm -f "$RETRIED_LIST"' EXIT

run_one() {
    local test_file="$1"
    local name
    name=$(basename "$test_file" .sh)
    local out="${SCRIPT_DIR}/run--${name}.out"
    # CB_NO_BUILD_PROGRESS: this runner owns the terminal line; a child drawing
    # its own on top of it would leave both illegible.
    if (cd "$SCRIPT_DIR" && CB_NO_BUILD_PROGRESS=1 bash "$test_file" $VERBOSE) > "$out" 2>&1; then
        echo 0 > "${out}.exit"
        return
    fi

    # Retry once, immediately. These are the flakiest tests in the repo — VHS
    # drives a real terminal and a redraw that lands late loses a keystroke — so
    # a second attempt is worth more here than anywhere else. `skip` in
    # tui-helpers--source.sh exits 0, so a skipped test never reaches this.
    #
    # This runs in a background subshell, so the retry is recorded in a file; an
    # array assignment here would not survive back to the parent.
    echo "" >> "$out"
    echo "⚠️  First attempt failed — retrying once." >> "$out"
    printf '%s\n' "$name" >> "$RETRIED_LIST"

    if (cd "$SCRIPT_DIR" && CB_NO_BUILD_PROGRESS=1 bash "$test_file" $VERBOSE) >> "$out" 2>&1; then
        echo 0 > "${out}.exit"
    else
        echo 1 > "${out}.exit"
    fi
}

print_result() {
    local test_file="$1"
    local name
    name=$(basename "$test_file" .sh)
    local out="${SCRIPT_DIR}/run--${name}.out"
    progress_clear
    echo "-------------------------------------------------------------------------------"
    [[ -f "$out" ]] && cat "$out"
    local exit_code=0
    [[ -f "${out}.exit" ]] && { exit_code=$(cat "${out}.exit"); rm -f "${out}.exit"; }
    rm -f "$out"
    echo ""
    return "$exit_code"
}

# What a VHS test is doing, on one self-erasing line. The last line of the test's
# own output is the useful half -- it says whether VHS is still recording, still
# encoding, or the assertions have started. Refreshed once a second, since it
# costs a `tail`.
_TUI_DETAIL=""
_TUI_DETAIL_AT=-1

draw_running() {
    [ "$PROGRESS_ACTIVE" = true ] || return 0

    local names="$1" started="$2" out="$3" el
    progress_elapsed_var el "$started" "$(date +%s)"

    if [[ -n "$out" ]] && (( SECONDS != _TUI_DETAIL_AT )); then
        _TUI_DETAIL=$(progress_tail "$out" 80)
        _TUI_DETAIL_AT=$SECONDS
        # A test's own first line is `Begin <testname>`, which this line already
        # carries. Echoing it back spends half the row repeating the name until
        # the test says something of its own.
        [[ "$_TUI_DETAIL" == "Begin "* ]] && _TUI_DETAIL=""
    fi

    if [[ -n "$_TUI_DETAIL" ]]; then
        progress_draw "${names} ${el}  — ${_TUI_DETAIL}"
    else
        progress_draw "${names} ${el}"
    fi
}

if [[ "$PARALLEL" -le 1 ]]; then
    for test_file in "${tests[@]}"; do
        name=$(basename "$test_file" .sh)
        progress_clear
        echo "Begin $name"

        # Backgrounded only so this loop stays awake to redraw the line; it is
        # still one test at a time, and the wait below is the same barrier the
        # foreground call was.
        started=$(date +%s)
        _TUI_DETAIL=""          # the previous test's last line is not this one's
        run_one "$test_file" &
        run_pid=$!
        while kill -0 "$run_pid" 2>/dev/null; do
            draw_running "$name" "$started" "${SCRIPT_DIR}/run--${name}.out"
            sleep 0.2
        done
        wait "$run_pid" 2>/dev/null

        if print_result "$test_file"; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAIL_TESTS+=("$name")
        fi
    done
else
    declare -a slot_pids=() slot_files=()
    qi=0
    PAR_START=$(date +%s)
    for (( s=0; s<PARALLEL && qi<TOTAL; s++, qi++ )); do
        progress_clear
        echo "Begin $(basename "${tests[$qi]}" .sh)"
        run_one "${tests[$qi]}" & slot_pids[$s]=$!; slot_files[$s]="${tests[$qi]}"
    done
    DONE=0
    while (( DONE < TOTAL )); do
        for (( s=0; s<${#slot_pids[@]}; s++ )); do
            pid=${slot_pids[$s]}; [[ -z "$pid" ]] && continue
            if ! kill -0 "$pid" 2>/dev/null; then
                wait "$pid" 2>/dev/null; DONE=$((DONE + 1))
                if print_result "${slot_files[$s]}"; then
                    PASS_COUNT=$((PASS_COUNT + 1))
                else
                    FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("$(basename "${slot_files[$s]}" .sh)")
                fi
                if (( qi < TOTAL )); then
                    progress_clear
                    echo "Begin $(basename "${tests[$qi]}" .sh)"
                    run_one "${tests[$qi]}" & slot_pids[$s]=$!; slot_files[$s]="${tests[$qi]}"; qi=$((qi + 1))
                else
                    slot_pids[$s]=""; slot_files[$s]=""
                fi
            fi
        done

        running=0
        for (( s=0; s<${#slot_pids[@]}; s++ )); do
            [[ -n "${slot_pids[$s]}" ]] && running=$(( running + 1 ))
        done
        (( running > 0 )) && draw_running "${running} recording" "$PAR_START" ""

        sleep 0.3
    done
fi

progress_clear

OVERALL_END=$(date +%s)
TEST_COUNT=$((PASS_COUNT + FAIL_COUNT))

echo "========================================"
echo "  Config-TUI Test Summary"
echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Failed: ${FAIL_COUNT}"
# A pass that needed a second attempt is still a flake — and in a timing-driven
# TUI suite that is the signal most worth keeping visible.
if [[ -s "$RETRIED_LIST" ]]; then
    echo "  ⚠️  Retried after a first-attempt failure: $(wc -l < "$RETRIED_LIST" | tr -d ' ')"
    sed 's/^/    - /' "$RETRIED_LIST"
fi
echo "  Duration: $((OVERALL_END - OVERALL_START))s"
echo "========================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for T in "${FAIL_TESTS[@]}"; do
        echo -e "  ❌ ${T}"
    done
    echo ""
    exit 1
fi

echo -e "\033[32m  All config-tui tests passed!\033[0m"
echo ""
