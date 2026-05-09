#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile kustomize Installation
#
# Verifies that `setup kustomize` installs the kustomize binary.
# `kustomize version` prints something like:
#   v5.4.3
# We match a v?X.Y.Z token to be format-tolerant across releases.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile kustomize Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- kustomize version 2>/dev/null | head -3)

if echo "$ACTUAL" | grep -qiE "v?[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "kustomize is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "kustomize should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
