#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: erlang--setup.sh documents and accepts the default OTP major.
#
# The 0.76.0 pin bump set OTP_DEFAULT_VERSION=28 while the allow-list still
# rejected anything but 25–27, so a default `setup erlang` / elixir's
# auto-install of Erlang failed before apt ran. --help is the user-facing
# contract of that list; the case statement is the actual gate.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/erlang--setup.sh"

FAILED=0

HELP_OUT=$(env EUID=0 "$SCRIPT" --help 2>&1) || true
if echo "$HELP_OUT" | grep -q "default (OTP 28)"; then
    print_test_result "true"  "$0" "1" "--help names OTP 28 as the default"
else
    print_test_result "false" "$0" "1" "--help should name OTP 28 as the default"
    echo "  out: $HELP_OUT"
    FAILED=$((FAILED + 1))
fi

if echo "$HELP_OUT" | grep -q "Supported OTP versions: 25, 26, 27, 28"; then
    print_test_result "true"  "$0" "2" "--help lists 28 as supported"
else
    print_test_result "false" "$0" "2" "--help should list 28 as supported"
    echo "  out: $HELP_OUT"
    FAILED=$((FAILED + 1))
fi

if grep -qE '25\|26\|27\|28' "$SCRIPT"; then
    print_test_result "true"  "$0" "3" "allow-list case includes 28"
else
    print_test_result "false" "$0" "3" "allow-list case should include 28"
    FAILED=$((FAILED + 1))
fi

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
