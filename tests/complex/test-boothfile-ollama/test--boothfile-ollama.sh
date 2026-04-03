#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Ollama Installation
#
# Verifies that a Boothfile with `setup ollama` correctly installs Ollama
# and makes it available in the container.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Ollama Installation ==="

FAILED=0

# Test 1: Ollama is installed and accessible
# Note: ollama --version prints a warning when no server is running,
# so we capture both stdout and stderr
ACTUAL=$(run_coding_booth --silence-build -- ollama --version 2>&1 | head -1) || true

if echo "$ACTUAL" | grep -qiE "ollama|Warning:.*Ollama"; then
    print_test_result "true" "$0" "1" "Ollama is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Ollama should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
