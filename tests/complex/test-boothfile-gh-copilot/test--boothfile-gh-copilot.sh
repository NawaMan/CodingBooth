#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile GitHub Copilot CLI Installation
#
# Verifies that a Boothfile with `setup gh` and `setup gh-copilot` correctly
# installs the GitHub CLI and sets up the Copilot extension scaffolding.
# Note: The actual extension binary requires GitHub auth, so we verify the
# setup artifacts (profile, startup, extensions dir) rather than the extension
# itself.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile GitHub Copilot CLI Installation ==="

FAILED=0

# Test 1: gh is installed and shows version
ACTUAL=$(run_coding_booth --silence-build -- gh --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qE "gh version"; then
    print_test_result "true" "$0" "1" "GitHub CLI is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "GitHub CLI should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: gh-copilot profile script is installed with aliases
PROFILE_CHECK=$(run_coding_booth --silence-build -- cat /etc/profile.d/71-cb-gh-copilot--profile.sh 2>&1) || true

if echo "$PROFILE_CHECK" | grep -q "copilot"; then
    print_test_result "true" "$0" "2" "GitHub Copilot profile script is installed"
else
    print_test_result "false" "$0" "2" "GitHub Copilot profile script should be installed"
    echo "  Actual output: $PROFILE_CHECK"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
