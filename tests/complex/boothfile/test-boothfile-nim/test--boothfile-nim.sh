#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Nim Installation
#
# Verifies that `setup nim` installs the Nim compiler.
# `nim --version` prints "Nim Compiler Version X.Y.Z [...]" on the first line.
#
# amd64 only: nim-lang.org publishes linux x64 builds and nothing for linux/arm64,
# so nim--setup.sh skips the install there (template: unsupported-arch).
# On an arm64 docker (Apple Silicon, Ubuntu on ARM) this test skips.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

SERVER_ARCH="$(docker_server_arch)"
if [[ "$SERVER_ARCH" != "amd64" ]]; then
    echo "SKIP: nim-lang.org publishes no linux/${SERVER_ARCH} build (linux x64 only); docker builds for '${SERVER_ARCH}' here." >&2
    exit 0
fi

echo "=== Test: Boothfile Nim Installation ==="

FAILED=0

ACTUAL=$(run_coding_booth --silence-build -- nim --version 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | head -1)

if echo "$ACTUAL" | grep -qiE "nim[^0-9]*[0-9]+\.[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "1" "Nim is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Nim should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
