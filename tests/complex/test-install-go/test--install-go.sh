#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile `install go` sanity check
#
# Verifies that the go install manager is reachable end-to-end:
#   1. `install go github.com/rakyll/hey@latest` compiles to RUN go--install.sh (known manager)
#   2. The package actually installs in a real build
#
# Test 1 is docker-free (emit-dockerfile only). Test 2 builds a real image and
# runs only when a locally-rebuilt base image is present (cb-local/codingbooth),
# because some go--install.sh scripts are newer than the Docker Hub base.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile install go ==="

FAILED=0

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

# Test 1: install go compiles to RUN go--install.sh (go is a known manager)
if echo "$DOCKERFILE" | grep -qE "RUN go--install\.sh" \
   && ! echo "$DOCKERFILE" | grep -q "Unknown install script 'go'"; then
    print_test_result "true" "$0" "1" "install go compiles to RUN go--install.sh"
else
    print_test_result "false" "$0" "1" "install go should compile to RUN go--install.sh"
    echo "  Dockerfile: $DOCKERFILE"
    FAILED=$((FAILED + 1))
fi

# The real build needs go--install.sh baked into the base image. Build against a
# locally-rebuilt base; skip (reporting the emit result) when one isn't present.
use_local_base_image || exit $FAILED

# Test 2: the package actually installs and is usable
ACTUAL=$(run_coding_booth --silence-build -- 'command -v hey' 2>/dev/null) || ACTUAL=""
if echo "$ACTUAL" | grep -qE 'hey'; then
    print_test_result "true" "$0" "2" "hey is on PATH"
else
    print_test_result "false" "$0" "2" "hey is on PATH"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: GOBIN is exported and points where `install go` puts binaries.
# PATH alone is not enough — tooling that reads GOBIN rather than scanning PATH
# (the VS Code Go extension, `go install` itself when re-run) needs the variable
# set, and its absence is invisible until such a tool silently looks elsewhere.
# Rides this build rather than paying for its own.
ACTUAL=$(run_coding_booth --silence-build -- 'echo "$GOBIN"' 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "/home/coder/go/bin" ]]; then
    print_test_result "true" "$0" "3" "GOBIN is exported as \$GOPATH/bin"
else
    print_test_result "false" "$0" "3" "GOBIN should be exported as /home/coder/go/bin"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: and the installed binary really is in that directory, so GOBIN is not
# merely set to a plausible-looking path that nothing writes to.
ACTUAL=$(run_coding_booth --silence-build -- 'ls "$GOBIN" 2>/dev/null | grep -cx hey' 2>/dev/null | tail -1) || ACTUAL=""
if [[ "$ACTUAL" == "1" ]]; then
    print_test_result "true" "$0" "4" "the installed binary is in \$GOBIN"
else
    print_test_result "false" "$0" "4" "the installed binary should be in \$GOBIN"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

exit $FAILED
