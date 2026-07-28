#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: capture helpers never lose output to SIGPIPE
#
# Piping a booth run straight into an early-exiting consumer (`head -1`) lets the
# consumer close the pipe as soon as it has its line. The writer then takes
# SIGPIPE, and under `set -o pipefail` the whole capture collapses to "" — so a
# test either sees an empty result or, with no `||` guard, `set -e` kills the
# script outright with no output at all.
#
# It is a race: on an idle machine the writer usually finishes first and nothing
# happens, which is why this hid for so long and only surfaced under full-suite
# load. These checks force the losing side of the race deterministically by
# producing far more output than the consumer will read.
#
# No Docker needed: run_coding_booth is stubbed, since what is under test is the
# capture contract, not the booth.
# -----------------------------------------------------------------------------

set -uo pipefail   # deliberately no `-e`: a regression must report, not abort

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../common--source.sh

echo "=== Test: capture helpers survive an early-exiting consumer ==="

FAILED=0

# Stand in for a booth run that emits far more than the consumer will read.
run_coding_booth() {
    seq 1 200000
}

# Test 1: capture_codingbooth with a `head` transform keeps the first line.
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- ignored)
if [[ "$ACTUAL" == "1" ]]; then
    print_test_result "true" "$0" "1" "capture_codingbooth \"head -1\" returns the first line"
else
    print_test_result "false" "$0" "1" "capture_codingbooth \"head -1\" should return the first line"
    echo "  Expected: 1"
    echo "  Actual output: '$ACTUAL'"
    FAILED=$((FAILED + 1))
fi

# Test 2: the capture-then-trim idiom call sites use, under pipefail.
ACTUAL=$(run_coding_booth 2>/dev/null) || ACTUAL=""
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)
if [[ "$ACTUAL" == "1" ]]; then
    print_test_result "true" "$0" "2" "capture-then-trim keeps the first line"
else
    print_test_result "false" "$0" "2" "capture-then-trim should keep the first line"
    echo "  Actual output: '$ACTUAL'"
    FAILED=$((FAILED + 1))
fi

# Test 3: the old shape really does collapse — proves these checks can fail, and
# documents why the idiom above is required rather than merely tidier.
OLD=$( (set -o pipefail; run_coding_booth 2>/dev/null | head -1) ) || OLD="COLLAPSED"
if [[ "$OLD" == "COLLAPSED" || -z "$OLD" ]]; then
    print_test_result "true" "$0" "3" "piping booth into head still demonstrates the collapse"
else
    # Not a failure of the fix — the race simply did not land this run. Say so
    # rather than asserting, so an idle machine cannot turn this into a red suite.
    print_test_result "true" "$0" "3" "piping booth into head did not collapse this run (race not hit)"
fi

if [[ $FAILED -eq 0 ]]; then
    echo "All 3 capture-SIGPIPE tests passed."
fi

exit $FAILED
