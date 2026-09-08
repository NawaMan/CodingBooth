#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Failure branches of anythingllm--setup.sh. The happy path writes to
# /usr/local/bin and needs the app tree from the official image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/anythingllm--setup.sh"

FAILED=0

# --help is parsed before the root guard.
HELP_OUT=$("$SCRIPT" --help 2>&1) || true
if echo "$HELP_OUT" | grep -q "start-anythingllm"; then
    print_test_result "true"  "$0" "1" "--help mentions start-anythingllm"
else
    print_test_result "false" "$0" "1" "--help should mention start-anythingllm"
    FAILED=$((FAILED + 1))
fi

NOTROOT_OUT=$("$SCRIPT" 2>&1) && notroot_rc=0 || notroot_rc=$?
if [[ "$notroot_rc" -ne 0 ]] && echo "$NOTROOT_OUT" | grep -q "Run as root"; then
    print_test_result "true"  "$0" "2" "non-root invocation is rejected"
else
    print_test_result "false" "$0" "2" "non-root should fail; rc=$notroot_rc out=$NOTROOT_OUT"
    FAILED=$((FAILED + 1))
fi

MISSING_OUT=$(env EUID=0 "$SCRIPT" 2>&1) && missing_rc=0 || missing_rc=$?
if [[ "$missing_rc" -ne 0 ]] && echo "$MISSING_OUT" | grep -qE "AnythingLLM not found|Run as root"; then
    print_test_result "true"  "$0" "3" "missing /opt/anythingllm or non-root fails with an explanation"
else
    print_test_result "false" "$0" "3" "missing tree should fail; rc=$missing_rc out=$MISSING_OUT"
    FAILED=$((FAILED + 1))
fi

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
