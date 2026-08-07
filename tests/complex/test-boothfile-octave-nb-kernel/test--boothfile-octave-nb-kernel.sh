#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile octave-nb-kernel Installation
#
# Verifies that `setup notebook` + `setup octave` + `setup octave-nb-kernel`
# registers an Octave kernel with Jupyter AND that the kernel actually returns
# plots as images.
#
# The second half matters: octave_kernel only captures figures when its backend
# starts with "inline". Configured with a bare toolkit name it draws live
# instead, and with no display server gnuplot falls back to its ASCII "dumb"
# terminal — the notebook cell then shows unreadable text art where the figure
# should be. A kernelspec-only check happily passes in that state, so this test
# drives a real plotting cell over the Jupyter protocol.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile octave-nb-kernel Installation ==="

FAILED=0

# Test 1: the kernelspec is registered.
ACTUAL=$(run_coding_booth --silence-build -- jupyter kernelspec list 2>&1 | grep -v '^> codingbooth' || true)

if echo "$ACTUAL" | grep -qiE '^\s*octave\s'; then
    print_test_result "true" "$0" "1" "octave kernel is registered with Jupyter"
else
    print_test_result "false" "$0" "1" "octave kernel should be listed by 'jupyter kernelspec list'"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: the kernel is configured for inline capture, not a live backend.
CONFIG=$(run_coding_booth --silence-build -- 'cat /usr/local/etc/jupyter/octave_kernel_config.py' 2>&1 | grep -v '^> codingbooth' || true)

if echo "$CONFIG" | grep -q "backend='inline"; then
    print_test_result "true" "$0" "2" "octave_kernel backend is an inline backend"
else
    print_test_result "false" "$0" "2" "octave_kernel backend must start with 'inline' or plots render as ASCII"
    echo "  Actual output: $CONFIG"
    FAILED=$((FAILED + 1))
fi

# Test 3/4/5: a real plotting cell comes back as an image, not text art.
PROBE=$(run_coding_booth --silence-build -- 'python /home/coder/code/kernel-plot-probe.py' 2>&1 | grep -v '^> codingbooth' || true)
PROBE_LINE=$(printf '%s\n' "$PROBE" | grep '^PROBE mimetypes=' || true)

if echo "$PROBE_LINE" | grep -q 'mimetypes=.*image/png'; then
    print_test_result "true" "$0" "3" "plotting cell returns an image/png figure"
else
    print_test_result "false" "$0" "3" "plotting cell should return an image/png figure"
    echo "  Actual output: $PROBE"
    FAILED=$((FAILED + 1))
fi

if echo "$PROBE_LINE" | grep -q 'ascii=no'; then
    print_test_result "true" "$0" "4" "plotting cell does not emit an ASCII plot"
else
    print_test_result "false" "$0" "4" "plotting cell should not emit an ASCII 'dumb' terminal plot"
    echo "  Actual output: $PROBE"
    FAILED=$((FAILED + 1))
fi

if echo "$PROBE_LINE" | grep -q 'warning=no'; then
    print_test_result "true" "$0" "5" "no 'gnuplot toolkit is discouraged' warning in cell output"
else
    print_test_result "false" "$0" "5" "the gnuplot toolkit warning should be suppressed"
    echo "  Actual output: $PROBE"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
