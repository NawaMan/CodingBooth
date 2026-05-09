#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile stern Installation
#
# Verifies that `setup stern` installs the stern binary.
# stern doesn't need a cluster to report --version output.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile stern Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- stern --version 2>/dev/null | head -3)

if echo "$ACTUAL" | grep -qiE "version[^0-9]*v?[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "stern is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "stern should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
