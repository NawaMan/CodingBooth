#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Swift Installation
#
# Verifies that a Boothfile with `setup swift --version 6.0.1` installs Swift
# and exposes it on PATH.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

# Hub swift--setup.sh downloads the x86_64 tarball even on arm64; the local
# image has a fix that appends -aarch64 to the path/tarball when needed.
use_local_base_image || exit 0

echo "=== Test: Boothfile Swift Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- swift --version 2>/dev/null | head -1)

if echo "$ACTUAL" | grep -qiE "swift version"; then
    print_test_result "true" "$0" "1" "Swift is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Swift should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
