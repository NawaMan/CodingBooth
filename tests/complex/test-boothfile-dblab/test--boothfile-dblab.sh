#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile dblab Installation
#
# Verifies that a Boothfile with `setup dblab` correctly installs dblab AND
# that it actually reaches a real database — a local PostgreSQL server also
# installed in the same booth — rather than only proving a binary landed on
# PATH.
#
# dblab's TUI needs a real terminal, so a full session cannot be driven here.
# Instead: connect with its real --host/--port/--user/--db flags and no TTY.
# A failed connection (bad host/db/creds) prints a "pq: ..." error before
# dblab ever touches the terminal. A successful one only fails afterward, on
# opening a TTY for the TUI (bubbletea) — which is what proves it connected.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile dblab Installation ==="

FAILED=0

# Test 1: dblab is installed and accessible
ACTUAL=$(run_coding_booth --silence-build -- dblab version 2>&1)

if echo "$ACTUAL" | grep -qiE "dblab version"; then
    print_test_result "true" "$0" "1" "dblab is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "dblab should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: it actually connects to a real PostgreSQL database
# CodingBooth's postgresql setup grants the container user a passwordless
# superuser role but creates no database matching that user's name, so the
# always-present "postgres" database is the connection target here.
ACTUAL=$(run_coding_booth --silence-build -- \
  'sleep 2; dblab --host localhost --port 5432 --user coder --db postgres --driver postgres </dev/null' \
  2>&1) || true

if echo "$ACTUAL" | grep -qiE "bubbletea|error opening TTY"; then
    print_test_result "true" "$0" "2" "dblab connects to a real PostgreSQL database"
else
    print_test_result "false" "$0" "2" "dblab should connect to a real PostgreSQL database"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
