#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile HeidiSQL Installation
#
# Verifies that a Boothfile with `setup heidisql` installs HeidiSQL, from
# CodingBoothPrebuilt on amd64 and arm64 alike. HeidiSQL is a GUI app with no
# headless query mode, so an executable whose libraries all resolve is the
# strongest check available without a display.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

echo "=== Test: Boothfile HeidiSQL Installation ==="

FAILED=0

# Test 1: HeidiSQL is genuinely installed, with every library it links found
# (libQt6Pas comes inside the prebuilt, Qt6 from apt).
ACTUAL=$(run_coding_booth --silence-build -- \
  'f=$(readlink -f "$(command -v heidisql)"); echo "$f"; ldd "$f" | grep -c "not found"' 2>/dev/null)
if [[ "$(printf '%s\n' "$ACTUAL" | tail -2 | head -1)" == /opt/heidisql/heidisql-*/heidisql \
      && "$(printf '%s\n' "$ACTUAL" | tail -1)" == 0 ]]; then
    print_test_result "true" "$0" "1" "HeidiSQL is installed via Boothfile, with its libraries"
else
    print_test_result "false" "$0" "1" "HeidiSQL should be installed with all its libraries"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

# Test 2: the binary itself is on PATH
ACTUAL=$(run_coding_booth --silence-build -- "command -v heidisql" 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | tail -1)
if [[ "$ACTUAL" == "/usr/local/bin/heidisql" ]]; then
    print_test_result "true" "$0" "2" "heidisql is on PATH"
else
    print_test_result "false" "$0" "2" "heidisql should be on PATH"
    echo "  Actual output: ${ACTUAL:-<empty>}"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
