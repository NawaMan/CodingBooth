#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile VHS Installation
#
# Verifies that `setup vhs` installs the VHS (Charmbracelet) binary for
# recording terminal/TUI sessions as GIF/MP4 from .tape scripts.
# `vhs --version` should print a version string.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile VHS Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- vhs --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "vhs|[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "vhs is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "vhs should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
