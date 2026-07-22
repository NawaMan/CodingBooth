#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile mkcert Installation
#
# Verifies that `setup mkcert` installs the mkcert binary.
# Note: mkcert uses single-dash flags: `mkcert -version`, not --version.
# Output: "vX.Y.Z" on a single line.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile mkcert Installation ==="

FAILED=0

# This test builds an image that downloads mkcert from GitHub, so a failure is
# usually a build/network failure rather than a missing binary. Keep the build
# stderr so the next failure is diagnosable instead of silent.
export CB_STDERR_LOG="${SCRIPT_DIR}/../../logs/test-boothfile-mkcert.stderr.log"
mkdir -p "$(dirname "$CB_STDERR_LOG")"
: >"$CB_STDERR_LOG"

ACTUAL=$(capture_codingbooth "head -1" --silence-build -- mkcert -version)

if echo "$ACTUAL" | grep -qE "v?[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "mkcert is installed via Boothfile"
    rm -f "$CB_STDERR_LOG"
else
    print_test_result "false" "$0" "1" "mkcert should be installed"
    echo "  Actual output: $ACTUAL"
    echo "  Build stderr: $CB_STDERR_LOG"
    tail -30 "$CB_STDERR_LOG" 2>/dev/null | sed 's/^/    /'
    FAILED=$((FAILED + 1))
fi

exit $FAILED
