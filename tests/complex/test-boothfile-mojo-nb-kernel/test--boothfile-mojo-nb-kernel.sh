#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile mojo-nb-kernel
#
# Registers a kernelspec named `mojo` and runs a %%mojo cell that prints
# "Hello from Mojo". That is the first-five-minutes check — not only
# `jupyter kernelspec list`.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Mojo notebook kernel ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'jupyter kernelspec list' ) || ACTUAL=""
if echo "$ACTUAL" | grep -qiE '^\s*mojo\s'; then
    print_test_result "true" "$0" "1" "mojo kernel is registered with Jupyter"
else
    print_test_result "false" "$0" "1" "mojo kernel should be listed by jupyter kernelspec list"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

PROBE=$(capture_codingbooth "cat" --silence-build -- 'python /home/coder/code/kernel-mojo-probe.py') || PROBE=""
PROBE_LINE=$(printf '%s\n' "$PROBE" | grep '^PROBE text=' || true)

if echo "$PROBE_LINE" | grep -q "Hello from Mojo" && echo "$PROBE_LINE" | grep -q "error=no"; then
    print_test_result "true" "$0" "2" "%%mojo cell prints Hello from Mojo"
else
    print_test_result "false" "$0" "2" "%%mojo cell should print Hello from Mojo"
    echo "  Actual output: $PROBE"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
