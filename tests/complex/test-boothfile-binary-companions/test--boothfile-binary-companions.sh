#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: Boothfile binary companions (Phase 1)
#
# Builds a real booth from a Boothfile that matches the Phase 1 config
# templates (ffmpeg, graphviz, protobuf/protoc, buf, Go protoc plugins) and
# checks that each tool is on PATH and reports a version. Proves the booth
# starts and the install/setup segments work end-to-end — not only that
# `booth config` emits the right Boothfile lines.
#
# buf is loaded from .booth/setups/buf--setup.sh (mirrors
# variants/base/setups/buf--setup.sh) so the test works before the script
# ships in the Docker Hub base image.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: Boothfile binary companions (Phase 1) ==="

FAILED=0
export CB_STDERR_LOG="${SCRIPT_DIR}/.test-stderr.log"
: >"$CB_STDERR_LOG"

# Helper: run a command in the booth, keep first line of stdout.
booth_first() {
    capture_codingbooth "head -1" --silence-build -- "$@"
}

# Test 1: booth starts and can run a trivial command
ACTUAL=$(booth_first echo binary-companions-ok) || ACTUAL=""
if [[ "$ACTUAL" == "binary-companions-ok" ]]; then
    print_test_result "true" "$0" "1" "booth starts and runs a command"
else
    print_test_result "false" "$0" "1" "booth should start and run a command"
    echo "  Actual output: $ACTUAL"
    echo "  (see $CB_STDERR_LOG for build/run stderr)"
    FAILED=$((FAILED + 1))
fi

# Test 2: ffmpeg (templates/tools/ffmpeg)
ACTUAL=$(booth_first ffmpeg -version) || ACTUAL=""
if echo "$ACTUAL" | grep -qiE '^ffmpeg version'; then
    print_test_result "true" "$0" "2" "ffmpeg is installed and on PATH"
else
    print_test_result "false" "$0" "2" "ffmpeg should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 3: graphviz / dot (templates/tools/graphviz)
# `dot -V` writes to stderr; run as one booth arg so the shell inside captures it.
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -c "dot -V 2>&1"') || ACTUAL=""
if echo "$ACTUAL" | grep -qiE 'graphviz|dot - graphviz'; then
    print_test_result "true" "$0" "3" "graphviz (dot) is installed and on PATH"
else
    print_test_result "false" "$0" "3" "graphviz (dot) should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 4: protoc (templates/tools/protobuf)
ACTUAL=$(booth_first protoc --version) || ACTUAL=""
if echo "$ACTUAL" | grep -qiE 'libprotoc|protoc'; then
    print_test_result "true" "$0" "4" "protoc is installed and on PATH"
else
    print_test_result "false" "$0" "4" "protoc should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 5: buf CLI (templates/tools/buf + setup buf)
ACTUAL=$(booth_first buf --version) || ACTUAL=""
if echo "$ACTUAL" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then
    print_test_result "true" "$0" "5" "buf is installed and on PATH"
else
    print_test_result "false" "$0" "5" "buf should be installed"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 6: protoc-gen-go (protobuf+go extension) — login shell for GOPATH/bin
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "protoc-gen-go --version"') || ACTUAL=""
if echo "$ACTUAL" | grep -qiE 'protoc-gen-go'; then
    print_test_result "true" "$0" "6" "protoc-gen-go is on PATH"
else
    print_test_result "false" "$0" "6" "protoc-gen-go should be on PATH"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 7: protoc-gen-go-grpc (protobuf+go extension)
ACTUAL=$(capture_codingbooth "head -1" --silence-build -- 'bash -lc "command -v protoc-gen-go-grpc"') || ACTUAL=""
if echo "$ACTUAL" | grep -q 'protoc-gen-go-grpc'; then
    print_test_result "true" "$0" "7" "protoc-gen-go-grpc is on PATH"
else
    print_test_result "false" "$0" "7" "protoc-gen-go-grpc should be on PATH"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

# Test 8: plugins are usable with protoc (end-to-end codegen smoke)
# Single booth arg (quoted) so the multi-line script is not split by the CLI.
ACTUAL=$(capture_codingbooth "tail -1" --silence-build -- 'bash -lc "
  set -e
  TMP=\$(mktemp -d)
  printf \"%s\\n\" \
    \"syntax = \\\"proto3\\\";\" \
    \"package hello;\" \
    \"option go_package = \\\"example.com/hello\\\";\" \
    \"message Ping { string msg = 1; }\" \
    >\"\$TMP/hello.proto\"
  protoc -I \"\$TMP\" --go_out=\"\$TMP\" --go_opt=paths=source_relative \"\$TMP/hello.proto\"
  test -f \"\$TMP/hello.pb.go\" && echo codegen-ok
"') || ACTUAL=""
if [[ "$ACTUAL" == "codegen-ok" ]]; then
    print_test_result "true" "$0" "8" "protoc + protoc-gen-go can generate Go sources"
else
    print_test_result "false" "$0" "8" "protoc + protoc-gen-go should generate Go sources"
    echo "  Actual output: $ACTUAL"
    FAILED=$((FAILED + 1))
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "Build/run stderr log: $CB_STDERR_LOG"
fi

exit $FAILED
