#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Script Validation
#
# Verifies that:
# 1. Unknown setup/install scripts produce warnings
# 2. Warnings include suggestions for similar scripts
# 3. Compilation succeeds despite warnings (non-strict mode)
# 4. --strict mode causes compilation to fail on warnings
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Script Validation ==="

FAILED=0

# Find codingbooth binary
BOOTH_PATH=""
CHECK_DIR="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -x "$CHECK_DIR/codingbooth" ]]; then
        BOOTH_PATH="$CHECK_DIR/codingbooth"
        break
    fi
    CHECK_DIR="$(dirname "$CHECK_DIR")"
done

if [[ -z "$BOOTH_PATH" ]]; then
    echo "ERROR: Could not find codingbooth"
    exit 1
fi

# -----------------------------------------------------------------------------
# Test 1: emit-dockerfile produces warnings for unknown scripts
# -----------------------------------------------------------------------------
OUTPUT=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" 2>&1) || true

if echo "$OUTPUT" | grep -q "Warning.*Unknown setup script 'pytohn'"; then
    print_test_result "true" "$0" "1" "Warning for unknown setup script 'pytohn'"
else
    print_test_result "false" "$0" "1" "Should warn about unknown setup script 'pytohn'"
    echo "  Output: $OUTPUT"
    FAILED=$((FAILED + 1))
fi

# -----------------------------------------------------------------------------
# Test 2: Warning includes suggestion for similar script
# -----------------------------------------------------------------------------
if echo "$OUTPUT" | grep -q "python"; then
    print_test_result "true" "$0" "2" "Warning suggests 'python' for 'pytohn'"
else
    print_test_result "false" "$0" "2" "Should suggest 'python' as alternative"
    echo "  Output: $OUTPUT"
    FAILED=$((FAILED + 1))
fi

# -----------------------------------------------------------------------------
# Test 3: Warning for unknown install script
# -----------------------------------------------------------------------------
if echo "$OUTPUT" | grep -q "Warning.*Unknown install script 'ppi'"; then
    print_test_result "true" "$0" "3" "Warning for unknown install script 'ppi'"
else
    print_test_result "false" "$0" "3" "Should warn about unknown install script 'ppi'"
    echo "  Output: $OUTPUT"
    FAILED=$((FAILED + 1))
fi

# -----------------------------------------------------------------------------
# Test 4: Compilation succeeds despite warnings (exit code 0)
# -----------------------------------------------------------------------------
if "$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" >/dev/null 2>&1; then
    print_test_result "true" "$0" "4" "Compilation succeeds with warnings (non-strict)"
else
    print_test_result "false" "$0" "4" "Compilation should succeed with warnings"
    FAILED=$((FAILED + 1))
fi

# -----------------------------------------------------------------------------
# Test 5: Dockerfile is still generated
# -----------------------------------------------------------------------------
DOCKERFILE=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" 2>/dev/null)

if echo "$DOCKERFILE" | grep -q "RUN pytohn--setup.sh 3.12"; then
    print_test_result "true" "$0" "5" "Dockerfile contains setup command despite warning"
else
    print_test_result "false" "$0" "5" "Dockerfile should contain the setup command"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# -----------------------------------------------------------------------------
# Test 6: --strict mode causes failure on warnings
# -----------------------------------------------------------------------------
if "$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" --strict >/dev/null 2>&1; then
    print_test_result "false" "$0" "6" "--strict mode should fail on warnings"
    FAILED=$((FAILED + 1))
else
    print_test_result "true" "$0" "6" "--strict mode fails on warnings"
fi

# -----------------------------------------------------------------------------
# Test 7: --strict mode error message mentions strict mode
# -----------------------------------------------------------------------------
STRICT_OUTPUT=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" --strict 2>&1) || true

if echo "$STRICT_OUTPUT" | grep -q "strict"; then
    print_test_result "true" "$0" "7" "Error message mentions --strict mode"
else
    print_test_result "false" "$0" "7" "Error message should mention --strict mode"
    echo "  Output: $STRICT_OUTPUT"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
