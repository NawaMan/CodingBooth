#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Grok (xAI) Installation
#
# Verifies that `setup grok` installs the lightweight grok CLI wrapper for
# xAI Grok models. We test `grok --help` because it succeeds without an
# XAI_API_KEY (the CLI prints usage and exits 0 for --help).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Grok (xAI) Installation ==="

FAILED=0

# grok --help prints usage without requiring an API key
ACTUAL=$(run_coding_booth --silence-build -- grok --help 2>&1 | head -5) || true

if echo "$ACTUAL" | grep -qiE "grok.*xai|chat with Grok|xAI Grok"; then
    print_test_result "true" "$0" "1" "grok CLI is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "grok CLI should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
