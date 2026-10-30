#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Goose (language) Installation
#
# Verifies that `setup goose-lang` gives a booth in which Goose runs a program
# in-process (bundled TinyCC + libc6-dev) and builds a native executable (gcc),
# and that it does not take the `goose` command from the Goose AI agent.
# Both setups download from GitHub releases, so this needs network.
#
# amd64 only: Goose publishes linux x64 builds and nothing for linux/arm64, so
# goose-lang--setup.sh skips the install there (template: unsupported-arch).
# On an arm64 docker (Apple Silicon, Ubuntu on ARM) this test skips.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

SERVER_ARCH="$(docker_server_arch)"
if [[ "$SERVER_ARCH" != "amd64" ]]; then
    echo "SKIP: Goose publishes no linux/${SERVER_ARCH} build (linux x64 only); docker builds for '${SERVER_ARCH}' here." >&2
    exit 0
fi

echo "=== Test: Boothfile Goose (language) Installation ==="

FAILED=0
EXPECTED="hello from goose: [0, 1, 4, 9, 16] 3 2"

# Test 1-3. No quotes in the script: it round-trips through codingbooth's COMMAND
# mode (argv -> joined string -> re-parsed by bash -c).
RUN_SCRIPT='
cd /tmp && cp /home/coder/code/hello.goose .
echo run: $(goose-lang hello.goose 2>/dev/null)
goose-lang build hello.goose -o hello >/dev/null 2>&1 && echo built: $(./hello)
echo agent: $(goose --version 2>&1 | head -1)
'
ACTUAL=$(run_coding_booth --silence-build -- bash -c "$RUN_SCRIPT" 2>/dev/null) || ACTUAL=""

if echo "$ACTUAL" | grep -qxF "run: $EXPECTED"; then
    print_test_result "true" "$0" "1" "goose-lang runs a program in-process"
else
    print_test_result "false" "$0" "1" "goose-lang should run hello.goose in-process"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if echo "$ACTUAL" | grep -qxF "built: $EXPECTED"; then
    print_test_result "true" "$0" "2" "goose-lang build makes a native executable"
else
    print_test_result "false" "$0" "2" "goose-lang build should make a working executable"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# The agent prints its own version banner; the language's binary would reject
# --version ("unknown option"), so this proves `goose` is still the agent.
if echo "$ACTUAL" | grep -E "^agent: " | grep -qvi "unknown option"  \
   && echo "$ACTUAL" | grep -qE "^agent: .*[0-9]+\.[0-9]+"; then
    print_test_result "true" "$0" "3" "goose is still the Goose AI agent"
else
    print_test_result "false" "$0" "3" "goose should still be the Goose AI agent"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
