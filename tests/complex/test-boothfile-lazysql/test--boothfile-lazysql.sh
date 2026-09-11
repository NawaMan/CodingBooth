#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile lazysql Installation
#
# Verifies that a Boothfile with `setup lazysql` correctly installs lazysql
# AND that it actually reaches a real database — a local PostgreSQL server
# also installed in the same booth — rather than only proving a binary landed
# on PATH.
#
# lazysql's TUI needs a real terminal, so a full session cannot be driven
# here. Instead: point it at the real PostgreSQL server with stdin closed and
# no TTY. If the connection itself fails (bad host/db/creds), lazysql prints a
# connection error and exits before ever touching the terminal. If the
# connection succeeds, it only fails afterward, on opening /dev/tty for the
# TUI — which is what proves it got past connecting.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile lazysql Installation ==="

FAILED=0

# Test 1: lazysql is installed and accessible
# lazysql prints -version to stderr (Go's flag package convention), so both
# streams are captured here rather than just stdout.
ACTUAL=$(run_coding_booth --silence-build -- lazysql -version 2>&1)

if echo "$ACTUAL" | grep -qiE "lazysql version"; then
    print_test_result "true" "$0" "1" "lazysql is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "lazysql should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: it actually connects to a real PostgreSQL database
# CodingBooth's postgresql setup grants the container user a passwordless
# superuser role but creates no database matching that user's name, so the
# always-present "postgres" database is the connection target here.
ACTUAL=$(run_coding_booth --silence-build -- \
  'sleep 2; lazysql "postgres://coder@localhost:5432/postgres?sslmode=disable" </dev/null' \
  2>&1 | tail -1) || true

if echo "$ACTUAL" | grep -qE "/dev/tty"; then
    print_test_result "true" "$0" "2" "lazysql connects to a real PostgreSQL database"
else
    print_test_result "false" "$0" "2" "lazysql should connect to a real PostgreSQL database"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
