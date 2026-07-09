#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile nginx Installation
#
# Verifies that `setup nginx` installs nginx.
# `nginx -v` prints "nginx version: nginx/X.Y.Z" to STDERR, so we need 2>&1 to
# capture it. run_coding_booth also writes its own trace line ("> codingbooth
# ...") to stderr, so rather than filtering that line out we select the version
# line positively — the trace says "nginx -v", never "nginx version", and this
# stays correct no matter what else the build prints to stderr.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile nginx Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- nginx -v 2>&1 | grep -iE 'nginx version' | head -1 || true)

if echo "$ACTUAL" | grep -qiE "nginx[^0-9]*[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "nginx is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "nginx should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
