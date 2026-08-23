#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: CB_DIAG_LOG booth call trace
#
# Complex tests capture booth with `2>/dev/null`, so a run that intermittently
# returns nothing leaves no evidence of why. run_coding_booth records the command,
# its exit code, and a copy of stderr whenever CB_DIAG_LOG is set.
#
# This is instrumentation meant to be trusted precisely when something else is
# already failing, so it needs its own guard: a trace that silently stops
# recording is worse than no trace at all. The checks below pin the four
# properties it has to keep.
#
# In particular the trace must never disturb stdout — buffering booth's stdout
# through a variable or a process substitution can drop output, which is the very
# symptom the trace exists to investigate.
#
# No Docker needed: `version` and an unknown flag exercise the same code path
# without starting a container.
# -----------------------------------------------------------------------------

set -uo pipefail   # no `-e`: a regression must be reported, not abort the script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../common--source.sh

echo "=== Test: CB_DIAG_LOG booth call trace ==="

FAILED=0

DIAG_LOG="$(mktemp)"
cleanup() { rm -f "$DIAG_LOG"; }
trap cleanup EXIT

# Test 1: stdout reaches the caller untouched while the trace is active.
export CB_DIAG_LOG="$DIAG_LOG"
ACTUAL=$(run_coding_booth version 2>/dev/null)
if echo "$ACTUAL" | grep -q "CodingBooth:"; then
    print_test_result "true" "$0" "1" "stdout passes through untouched while tracing"
else
    print_test_result "false" "$0" "1" "stdout should pass through untouched while tracing"
    echo "  Actual output: '$ACTUAL'"
    FAILED=$((FAILED + 1))
fi

# Test 2: the command and a zero exit code are recorded.
if grep -q "=== codingbooth version" "$DIAG_LOG" && grep -q -- "--- rc=0" "$DIAG_LOG"; then
    print_test_result "true" "$0" "2" "command and rc=0 are recorded"
else
    print_test_result "false" "$0" "2" "command and rc=0 should be recorded"
    echo "  Log: $(cat "$DIAG_LOG")"
    FAILED=$((FAILED + 1))
fi

# Test 3: stderr is captured even though the caller sends it to /dev/null, and a
# non-zero exit is propagated to the caller rather than swallowed. This is the
# whole point — the tests' own `2>/dev/null` is what made the transient invisible.
# Match on booth's error text ("unknown flag"), NOT on the flag name: the flag name
# also appears in the `=== codingbooth …` command line this trace writes itself, so
# grepping for it would pass even with stderr capture removed entirely.
: >"$DIAG_LOG"
run_coding_booth --definitely-not-a-flag >/dev/null 2>/dev/null
RC=$?
if [[ "$RC" -ne 0 ]] && grep -qi "unknown flag" "$DIAG_LOG"; then
    print_test_result "true" "$0" "3" "stderr is captured through the caller's 2>/dev/null"
else
    print_test_result "false" "$0" "3" "stderr should be captured through the caller's 2>/dev/null"
    echo "  Caller rc: $RC (expected non-zero)"
    echo "  Log: $(cat "$DIAG_LOG")"
    FAILED=$((FAILED + 1))
fi

# Test 4: the non-zero exit code is recorded, not just propagated.
if grep -qE -- "--- rc=[1-9]" "$DIAG_LOG"; then
    print_test_result "true" "$0" "4" "non-zero exit code is recorded"
else
    print_test_result "false" "$0" "4" "non-zero exit code should be recorded"
    echo "  Log: $(cat "$DIAG_LOG")"
    FAILED=$((FAILED + 1))
fi

# Test 5: it stays opt-in — nothing is written when CB_DIAG_LOG is unset.
unset CB_DIAG_LOG
: >"$DIAG_LOG"
booth_step 5 "booth version run with CB_DIAG_LOG unset" version \
    || FAILED=$((FAILED + 1))
if [[ ! -s "$DIAG_LOG" ]]; then
    print_test_result "true" "$0" "5" "no trace is written when CB_DIAG_LOG is unset"
else
    print_test_result "false" "$0" "5" "no trace should be written when CB_DIAG_LOG is unset"
    echo "  Log: $(cat "$DIAG_LOG")"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -eq 0 ]]; then
    echo "All 5 diag-trace tests passed."
fi

exit $FAILED
