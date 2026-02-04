#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0

# Test that --emit-dockerfile generates correct output from Boothfile

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

# Find the codingbooth binary
if [ -f "$EXAMPLE_DIR/booth" ]; then
    CB_BIN="$EXAMPLE_DIR/booth"
elif command -v codingbooth &> /dev/null; then
    CB_BIN="codingbooth"
else
    echo "SKIP: codingbooth binary not found"
    exit 0
fi

# Generate Dockerfile from Boothfile
OUTPUT=$("$CB_BIN" --code "$EXAMPLE_DIR" --emit-dockerfile 2>/dev/null)

# Verify key elements are present
EXPECTED_PATTERNS=(
    "# syntax=docker/dockerfile:1"
    "FROM nawaman/codingbooth"
    "ARG PY_VERSION=3.12"
    "ARG NODE_VERSION=20"
    "RUN python--setup.sh"
    "RUN nodejs--setup.sh"
    "RUN pip--install.sh flask requests pytest"
    "RUN npm--install.sh typescript prettier"
    "ENV FLASK_APP=app.py"
    "EXPOSE 5000"
    "EXPOSE 3000"
)

FAILED=0
for pattern in "${EXPECTED_PATTERNS[@]}"; do
    if ! echo "$OUTPUT" | grep -qF "$pattern"; then
        echo "FAIL: Missing expected pattern: $pattern"
        FAILED=1
    fi
done

if [ "$FAILED" -eq 0 ]; then
    echo "PASS: Boothfile generates correct Dockerfile"
else
    echo "---"
    echo "Generated output:"
    echo "$OUTPUT"
    exit 1
fi
