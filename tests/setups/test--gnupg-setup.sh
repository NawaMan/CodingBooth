#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Argument and root-guard branches of gnupg--setup.sh. The happy path builds
# GnuPG from source into /usr/local; the base image build is what covers it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/gnupg--setup.sh"

FAILED=0

HELP_OUT=$("$SCRIPT" --help 2>&1) && help_rc=0 || help_rc=$?
if [[ "$help_rc" -eq 0 ]] && echo "$HELP_OUT" | grep -q -- "--version <X.Y.Z>"; then
    print_test_result "true"  "$0" "1" "--help prints usage"
else
    print_test_result "false" "$0" "1" "--help should print usage; rc=$help_rc out=$HELP_OUT"
    FAILED=$((FAILED + 1))
fi

# Checked before the root guard, so a typo fails the same way for everyone.
BAD_OUT=$("$SCRIPT" --version 2.5 2>&1) && bad_rc=0 || bad_rc=$?
if [[ "$bad_rc" -eq 2 ]] && echo "$BAD_OUT" | grep -q "Not a GnuPG version: '2.5'"; then
    print_test_result "true"  "$0" "2" "a version that is not X.Y.Z is rejected"
else
    print_test_result "false" "$0" "2" "--version 2.5 should exit 2; rc=$bad_rc out=$BAD_OUT"
    FAILED=$((FAILED + 1))
fi

if [[ $EUID -ne 0 ]]; then
    NOTROOT_OUT=$("$SCRIPT" 2>&1) && notroot_rc=0 || notroot_rc=$?
    if [[ "$notroot_rc" -ne 0 ]] && echo "$NOTROOT_OUT" | grep -q "Run as root"; then
        print_test_result "true"  "$0" "3" "non-root invocation is rejected"
    else
        print_test_result "false" "$0" "3" "non-root should fail; rc=$notroot_rc out=$NOTROOT_OUT"
        FAILED=$((FAILED + 1))
    fi
fi

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
