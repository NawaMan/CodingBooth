#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile `install dotnet` (global .NET tools)
#
# Verifies that the dotnet install manager is reachable end-to-end:
#   1. `install dotnet …` compiles to RUN dotnet--install.sh (known manager)
#   2. A real booth with setup dotnet + install dotnet-ef starts and has the
#      tool on PATH (dotnet-ef / `dotnet ef`)
#
# The install script is supplied under .booth/setups/ (mirrors
# variants/base/setups/dotnet--install.sh) so the test works before the script
# ships in the Docker Hub base image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile install dotnet (global tools) ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# Locate the codingbooth binary for the docker-free emit-dockerfile check.
BOOTH_PATH=""
CHECK_DIR="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    if [[ -f "$CHECK_DIR/codingbooth" && -x "$CHECK_DIR/codingbooth" ]]; then
        BOOTH_PATH="$CHECK_DIR/codingbooth"
        break
    fi
    CHECK_DIR="$(dirname "$CHECK_DIR")"
done
if [[ -z "$BOOTH_PATH" ]]; then
    echo "ERROR: Could not find codingbooth"
    exit 1
fi

DOCKERFILE=$("$BOOTH_PATH" emit-dockerfile --code "$SCRIPT_DIR" 2>&1) || true

# Test 1: install dotnet compiles to RUN dotnet--install.sh (dotnet is a known manager)
if echo "$DOCKERFILE" | grep -qE "RUN dotnet--install\.sh" \
   && ! echo "$DOCKERFILE" | grep -q "Unknown install script 'dotnet'"; then
    print_test_result "true" "$0" "1" "install dotnet compiles to RUN dotnet--install.sh"
else
    print_test_result "false" "$0" "1" "install dotnet should compile to RUN dotnet--install.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# Test 2: booth starts with the configured .NET tools
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- echo dotnet-tools-ok) || ACTUAL=""
if [[ "$ACTUAL" == "dotnet-tools-ok" ]]; then
    print_test_result "true" "$0" "2" "booth starts with install dotnet in Boothfile"
else
    print_test_result "false" "$0" "2" "booth should start with install dotnet in Boothfile"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

# Test 3: dotnet-ef shim is on PATH (login shell for ~/.dotnet/tools)
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "command -v dotnet-ef"') || ACTUAL=""
if echo "$ACTUAL" | grep -q 'dotnet-ef'; then
    print_test_result "true" "$0" "3" "dotnet-ef is on PATH"
else
    print_test_result "false" "$0" "3" "dotnet-ef should be on PATH"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: `dotnet ef` is usable (Entity Framework CLI entrypoint).
# Output is multi-line ("Entity Framework Core .NET Command-line Tools" then a version).
ACTUAL=$(capture_codingbooth "cat" --silence-build -- 'bash -lc "dotnet ef --version"') || ACTUAL=""
if echo "$ACTUAL" | grep -qiE 'Entity Framework' && echo "$ACTUAL" | grep -qE '[0-9]+\.[0-9]+'; then
    print_test_result "true" "$0" "4" "dotnet ef reports a version"
else
    print_test_result "false" "$0" "4" "dotnet ef should report a version"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
