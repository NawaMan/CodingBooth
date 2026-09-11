#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile sql-studio Installation
#
# Verifies that a Boothfile with `setup sql-studio` correctly installs
# sql-studio AND that it actually serves a real HTTP response, not just that
# a binary landed on PATH. start-sql-studio (its own launcher, registered as
# the desktop-icon starter) is run in the background against the built-in
# "preview" sample database, then queried with curl.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile sql-studio Installation ==="

FAILED=0

# Test 1: sql-studio is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- sql-studio --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "sql-studio [0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "sql-studio is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "sql-studio should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: start-sql-studio actually serves the preview sample over HTTP
ACTUAL=$(run_coding_booth --silence-build -- \
  "start-sql-studio & sleep 2; curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3030/" \
  2>/dev/null | tail -1)

if [[ "$ACTUAL" == "200" ]]; then
    print_test_result "true" "$0" "2" "sql-studio serves a real HTTP response"
else
    print_test_result "false" "$0" "2" "sql-studio should serve a real HTTP response"
    echo "  Actual HTTP status: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
