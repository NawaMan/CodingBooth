#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Shared helpers for the config-tui test suite.
#
# These tests drive the *interactive* `booth config` TUI with VHS
# (charmbracelet/vhs), then assert on the generated .booth/ files and — for
# TUI-only signals — on the captured final terminal frame.
#
# This file is meant to be sourced, not executed directly.
# Usage: source "$(dirname "$0")/tui-helpers--source.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This file should be sourced, not executed directly." >&2
    echo "Usage: source \"\$(dirname \"\$0\")/tui-helpers--source.sh\"" >&2
    exit 1
fi

testname=$(basename "$0" .sh)
prj="$(pwd)/prj--${testname}"
log="$(pwd)/log--${testname}.log"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
FAIL_TESTS=()

VERBOSE=false
for arg in "$@"; do case "$arg" in --verbose) VERBOSE=true ;; esac ; done

# ── Repo / binary discovery ─────────────────────────────────────────
# Walk up to the directory that holds both the `codingbooth` binary and the
# `templates/` directory (same approach as tests/config/test-helpers--source.sh).
REPO_ROOT=""
BOOTH_BIN=""
TEMPLATES_PATH=""
_discover_repo() {
    local dir
    dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -x "$dir/codingbooth" && -d "$dir/templates" ]]; then
            REPO_ROOT="$dir"
            BOOTH_BIN="$dir/codingbooth"
            TEMPLATES_PATH="$dir/templates"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# ── Availability guard ──────────────────────────────────────────────
# Emit a SKIP: line and exit 0 when the VHS toolchain (or the binary) is
# missing, so the master runner reports this suite as "skipped", not "failed".
function require-tui-tools() {
    local missing=()
    for tool in vhs ttyd ffmpeg; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if ! _discover_repo; then
        missing+=("codingbooth-binary")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "SKIP: ${testname} — missing: ${missing[*]}"
        echo "  These TUI tests need VHS (charmbracelet/vhs) plus ttyd and ffmpeg,"
        echo "  and a built ./codingbooth binary. Build with build/cli-build.sh."
        exit 0
    fi
}

# In-place sed that works on both GNU and BSD.
#
# GNU sed takes `-i` with no argument; BSD/macOS sed requires a suffix and
# otherwise swallows the *script* as the backup extension, then tries to read the
# filename as the script — "unterminated substitute pattern", exit 1, file
# untouched. test14 and test18 seed their fixture with one of these and did not
# check the exit status, so on macOS they asserted that a pin survived a save
# when the pin had never been written. Detected by feature, not by uname.
function sed-inplace() {
    local script="$1" file="$2"
    if sed --version >/dev/null 2>&1; then
        sed -i "$script" "$file"
    else
        sed -i '' "$script" "$file"
    fi
}

# Run a command under a wall-clock limit, portably.
#
# `timeout` is GNU coreutils and macOS ships neither it nor Homebrew's
# `gtimeout` by default. The bare `timeout 120 vhs ...` this replaced failed
# with "command not found" (127), so vhs never ran, no frame was captured, and
# all 18 tests failed on assertions about files nothing had written — a
# toolchain gap wearing the costume of 18 product bugs.
#
# With no timeout binary the command runs unguarded, deliberately. A bash
# watchdog was tried first and had to be backed out: it needs the command in
# the background, and a backgrounded vhs cannot reach ttyd
# ("net::ERR_CONNECTION_REFUSED") — the guard broke the thing it guarded.
# `brew install coreutils` restores the limit here via gtimeout.
function run-with-timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
    else
        "$@"
    fi
}

# ── Tape authoring + run ────────────────────────────────────────────
# run-tui <mode> <keystrokes...>
#   mode = "save"  → append Ctrl+S (drive to generation, assert on files)
#          "save-confirm"
#                  → append Ctrl+S, then type the overwrite confirmation word.
#                    Needed whenever .booth/ holds hand-written content: the TUI
#                    refuses to save over it until the word is typed in full, so a
#                    plain "save" would silently leave the files untouched — and a
#                    test asserting "the hand-written value survived" would then
#                    pass for the wrong reason.
#          "save-beside"
#                  → append Ctrl+S then a bare Enter: keep the hand-written files
#                    and write the generated content beside them as <name>.new.
#          "frame" → leave the TUI displayed (final frame is the TUI), then
#                    quit without saving (Ctrl+Q, Enter). Used for frame checks.
#          "raw"   → append nothing; the caller's keystrokes are complete.
#
# Extra launch flags can be passed via the LAUNCH_ARGS array before calling
# (e.g. LAUNCH_ARGS=(--select go)). The tape is written with printf (never a
# heredoc — the dev shell colorizes heredoc/cat output and corrupts the tape).
LAUNCH_ARGS=()
#
# Set DISMISS_WARNING=true when the booth under test raises the startup warning
# dialog — e.g. it holds hand-written files, or .booth/ is not writable. That
# dialog swallows every key until it is dismissed, so a test that leaves it up
# would be driving an unresponsive TUI and quietly assert on nothing.
DISMISS_WARNING=false
function run-tui() {
    local mode="$1"; shift
    local tape="${prj}/run.tape"
    local launch="${BOOTH_BIN} config --templates-path ${TEMPLATES_PATH}"
    local arg
    for arg in "${LAUNCH_ARGS[@]}"; do
        launch="${launch} ${arg}"
    done

    {
        printf '%s\n' \
            'Output frame.txt' \
            'Set Shell "bash"' \
            'Set FontSize 14' \
            'Set Width 1280' \
            'Set Height 720' \
            'Hide' \
            "Type \"cd ${prj}\"" \
            'Enter' \
            'Type "clear"' \
            'Enter' \
            'Show' \
            "Type \"${launch}\"" \
            'Enter' \
            'Sleep 4s'
        # Clear the startup warning dialog, if this booth raises one.
        if [[ "$DISMISS_WARNING" == "true" ]]; then
            printf '%s\n' 'Enter' 'Sleep 700ms'
        fi
        # Test-specific keystrokes
        printf '%s\n' "$@"
        # Terminal action by mode
        case "$mode" in
            save)
                printf '%s\n' 'Ctrl+S' 'Sleep 3s'
                ;;
            save-confirm)
                printf '%s\n' 'Ctrl+S' 'Sleep 1s' 'Type "overwrite"' 'Sleep 500ms' 'Enter' 'Sleep 3s'
                ;;
            save-beside)
                # Ctrl+S then a bare Enter: keep the hand-written files, write the
                # generated content beside them as <name>.new.
                printf '%s\n' 'Ctrl+S' 'Sleep 1s' 'Enter' 'Sleep 3s'
                ;;
            frame)
                # The keystroke state is captured into the stacked frame dump;
                # then exit without saving (Ctrl+E, Enter) so nothing is written.
                printf '%s\n' 'Sleep 600ms' 'Ctrl+E' 'Sleep 500ms' 'Enter' 'Sleep 800ms'
                ;;
            raw)
                : ;;
        esac
    } > "$tape"

    echo "" >> "$log"
    echo "=== tape (${mode}) ===" >> "$log"
    cat "$tape" >> "$log"
    echo "=== vhs run ===" >> "$log"

    ( cd "$prj" && run-with-timeout 120 vhs "$tape" ) >> "$log" 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "  WARN: vhs exited with code ${rc}" >> "$log"
    fi

    # Strip ANSI from the captured frame for stable grep-based assertions.
    if [[ -f "${prj}/frame.txt" ]]; then
        sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "${prj}/frame.txt" > "${prj}/frame.clean.txt" 2>/dev/null \
            || cp "${prj}/frame.txt" "${prj}/frame.clean.txt"
        echo "=== captured frame (cleaned) ===" >> "$log"
        cat "${prj}/frame.clean.txt" >> "$log"
    else
        echo "  WARN: no frame.txt captured" >> "$log"
    fi
}

# ── Assertions ──────────────────────────────────────────────────────
# assert-line <file> <prefix> <expected> <message>
# Matches a line in a generated file that starts with <prefix>; the remainder
# must equal <expected>. (Same contract as tests/config/test-helpers--source.sh.)
function assert-line() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi
    TEST_COUNT=$((TEST_COUNT + 1))

    local FILE="${1}" PREFIX="${2}" EXPECTED="${3}" MESSAGE="${4}"
    _print_test_header "$MESSAGE"
    echo "## Test ${TEST_COUNT} (assert-line) ###############" >> $log

    local FOUND
    FOUND="$(grep "^${PREFIX}" "$FILE" 2>/dev/null | head -1)" || true
    echo "  assert-line: file='${FILE}' prefix='${PREFIX}' found='${FOUND}' expected='${PREFIX}${EXPECTED}'" >> $log

    if [[ "${FOUND}" != "${PREFIX}${EXPECTED}" ]]; then
        _fail "EXPECTED: ${PREFIX}${EXPECTED}" "FOUND   : ${FOUND}"
        return
    fi
    _pass
}

# assert-file-contains <file> <substring> <message>
function assert-file-contains() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi
    TEST_COUNT=$((TEST_COUNT + 1))

    local FILE="${1}" NEEDLE="${2}" MESSAGE="${3}"
    _print_test_header "$MESSAGE"
    echo "## Test ${TEST_COUNT} (assert-file-contains) #######" >> $log
    echo "  file='${FILE}' needle='${NEEDLE}'" >> $log

    if [[ -f "$FILE" ]] && grep -qF -- "${NEEDLE}" "$FILE" 2>/dev/null; then
        _pass
    else
        _fail "EXPECTED file to contain: ${NEEDLE}" "FILE    : ${FILE}"
    fi
}

# assert-file-not-contains <file> <substring> <message>
function assert-file-not-contains() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi
    TEST_COUNT=$((TEST_COUNT + 1))

    local FILE="${1}" NEEDLE="${2}" MESSAGE="${3}"
    _print_test_header "$MESSAGE"
    echo "## Test ${TEST_COUNT} (assert-file-not-contains) ###" >> $log
    echo "  file='${FILE}' needle='${NEEDLE}'" >> $log

    if [[ -f "$FILE" ]] && grep -qF -- "${NEEDLE}" "$FILE" 2>/dev/null; then
        _fail "EXPECTED file NOT to contain: ${NEEDLE}" "FILE    : ${FILE}"
    else
        _pass
    fi
}

# assert-file-missing <path> <message>  — assert a file/dir does NOT exist.
function assert-file-missing() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi
    TEST_COUNT=$((TEST_COUNT + 1))

    local PATH_="${1}" MESSAGE="${2}"
    _print_test_header "$MESSAGE"
    echo "## Test ${TEST_COUNT} (assert-file-missing) ########" >> $log

    if [[ ! -e "$PATH_" ]]; then
        _pass
    else
        _fail "EXPECTED not to exist: ${PATH_}"
    fi
}

# assert-frame <substring> <message>  — grep the cleaned captured frame.
function assert-frame() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi
    TEST_COUNT=$((TEST_COUNT + 1))

    local NEEDLE="${1}" MESSAGE="${2}"
    _print_test_header "$MESSAGE"
    echo "## Test ${TEST_COUNT} (assert-frame) ##############" >> $log
    echo "  needle='${NEEDLE}'" >> $log

    if [[ -f "${prj}/frame.clean.txt" ]] && grep -qF -- "${NEEDLE}" "${prj}/frame.clean.txt" 2>/dev/null; then
        _pass
    else
        _fail "EXPECTED frame to contain: ${NEEDLE}"
    fi
}

# ── Internal pass/fail plumbing ─────────────────────────────────────
function _print_test_header() {
    local MESSAGE="${1}"
    echo "" >> $log
    local width=64
    local label="${MESSAGE} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad
    pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    _CUR_TEST="Test ${TEST_COUNT}: ${label}"
    echo -n "${_CUR_TEST}${pad}"
    if [[ "$VERBOSE" == "true" ]]; then echo ""; else echo -n " "; fi
}

function _pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
}

function _fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("${_CUR_TEST}")
    echo -e "\033[31mFAILED\033[0m"
    local line
    for line in "$@"; do
        echo "  ${line}"
    done
}

function skip() {
    local reason="${1:-No reason given}"
    echo "SKIP: ${testname} — ${reason}"
    exit 0
}

function begin() {
    echo "Begin ${testname}" | tee $log
    require-tui-tools
    rm -Rf "$prj"
    mkdir -p "${prj}"
}

function finally() {
    if [[ "$VERBOSE" == "true" ]]; then echo ""; fi
    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        echo ""
        echo -e "== \033[31mSOME TEST FAIL\033[0m ============================================================="
        echo "  Total: ${TEST_COUNT}   Passed: ${PASS_COUNT}   Failed: ${FAIL_COUNT}"
        echo "-------------------------------------------------------------------------------"
        echo ""
        echo "Failed tests:"
        for T in "${FAIL_TESTS[@]}"; do
            echo -e "  ❌ ${T}"
        done
        echo ""
        echo "See the full log: cat $log"
        echo "Captured frame:   cat ${prj}/frame.clean.txt"
        echo "==============================================================================="
        exit 1
    fi
    echo -e "== \033[32mALL TEST PASS\033[0m =============================================================="
}
