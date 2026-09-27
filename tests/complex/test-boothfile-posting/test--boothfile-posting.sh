#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile Posting Installation
#
# Verifies that a Boothfile with `setup posting` installs the pinned default
# version of Posting AND that it actually works, not just that a binary landed
# on PATH. Posting's request editor is a TUI that needs a real terminal, but the
# same command has a non-interactive `posting import` — used here to turn a
# small OpenAPI spec into a collection, which is what a user does first with an
# existing API.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile Posting Installation ==="

FAILED=0

# Test 1: posting is installed at the pinned default version
# posting has no --version flag, so ask the venv's pip.
ACTUAL=$(run_coding_booth --silence-build -- /opt/posting/bin/pip show posting 2>/dev/null)
ACTUAL=$(printf '%s\n' "$ACTUAL" | grep '^Version:' || true)

if echo "$ACTUAL" | grep -qE "^Version: 2\.11\.0$"; then
    print_test_result "true" "$0" "1" "Posting 2.11.0 is installed via Boothfile"
else
    print_test_result "false" "$0" "1" "Posting 2.11.0 should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 2: it imports an OpenAPI spec into a collection of request files
# Everything after `--` is joined into one shell command line (docs/BOOTH_RUN.md),
# so the whole script goes in as a single quoted argument.
SPEC='openapi: 3.0.0\ninfo: {title: Pets, version: v1}\nservers: [{url: http://localhost:8080}]\npaths:\n  /pets:\n    get: {summary: List pets, responses: {default: {description: ok}}}\n'
ACTUAL=$(run_coding_booth --silence-build -- "cd /tmp && printf '$SPEC' > api.yaml && posting import api.yaml -o pets >/dev/null && cat 'pets/List pets.posting.yaml'" 2>/dev/null)

if echo "$ACTUAL" | grep -qE "^url: .*/pets$"; then
    print_test_result "true" "$0" "2" "Posting imports an OpenAPI spec into a request collection"
else
    print_test_result "false" "$0" "2" "Posting should import an OpenAPI spec into a request collection"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
