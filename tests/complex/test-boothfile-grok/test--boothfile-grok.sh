#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Grok Build (xAI) Installation
#
# Verifies that `setup grok` installs the official xAI Grok Build coding agent
# (binary: grok). We test `grok --help` because it succeeds without auth
# (prints usage and exits 0 for --help).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Grok Build (xAI) Installation ==="

FAILED=0

# grok --help prints usage without requiring login / an API key
ACTUAL=$(run_coding_booth --silence-build -- grok --help 2>&1 | head -5) || true

# Current Grok Build CLI banners as "Grok Build TUI"; also accept older strings.
if echo "$ACTUAL" | grep -qiE "Grok Build|Grok Build TUI|grok.*xai|xAI Grok|chat with Grok"; then
    print_test_result "true" "$0" "1" "grok CLI is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "grok CLI should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
