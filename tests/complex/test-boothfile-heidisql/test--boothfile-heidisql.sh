#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile HeidiSQL Installation
#
# Verifies that a Boothfile with `setup heidisql` correctly installs HeidiSQL
# on amd64 (its only supported architecture — see heidisql--setup.sh for why
# arm64 is skipped). HeidiSQL is a GUI app with no headless query mode, so
# `dpkg -s` genuinely installed rather than the apt-get -f -y fallback
# silently doing nothing is the strongest check available without a display.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile HeidiSQL Installation ==="

FAILED=0

# heidisql--setup.sh gates itself on amd64 — HeidiSQL's native Linux build only
# ships a packaged .deb for amd64 (see the setup script for the arm64 note), so
# on arm64 the tools this test asserts on are legitimately absent.
SERVER_ARCH="$(docker_server_arch)"
if [[ "$SERVER_ARCH" != "amd64" ]]; then
    echo "SKIP: HeidiSQL is amd64-only; docker builds for '${SERVER_ARCH}' here." >&2
    exit 0
fi

# Test 1: HeidiSQL is genuinely installed (not silently skipped by the
# apt-get -f -y fallback swallowing a real dependency failure).
ACTUAL=$(run_coding_booth --silence-build -- \
  "dpkg -s heidisql 2>&1 | grep '^Status:'" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == "Status: install ok installed" ]]; then
    print_test_result "true" "$0" "1" "HeidiSQL is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "HeidiSQL should be installed"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: the binary itself is on PATH
ACTUAL=$(run_coding_booth --silence-build -- "command -v heidisql" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)

if [[ "$ACTUAL" == "/usr/bin/heidisql" ]]; then
    print_test_result "true" "$0" "2" "heidisql is on PATH"
else
    print_test_result "false" "$0" "2" "heidisql should be on PATH"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
