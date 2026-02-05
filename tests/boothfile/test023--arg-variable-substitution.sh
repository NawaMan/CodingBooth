#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: arg with ${VAR} substitution in subsequent commands

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

arg NODE_VERSION=20
arg PYTHON_VERSION=3.12

setup nodejs ${NODE_VERSION}
setup python ${PYTHON_VERSION}
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

if echo "$ACTUAL" | grep -qF "ARG NODE_VERSION=20"; then
    print_test_result "true" "$0" "023" "ARG NODE_VERSION is present"
else
    print_test_result "false" "$0" "023" "ARG NODE_VERSION is present"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "ARG PYTHON_VERSION=3.12"; then
    print_test_result "true" "$0" "023" "ARG PYTHON_VERSION is present"
else
    print_test_result "false" "$0" "023" "ARG PYTHON_VERSION is present"
    ALL_PASSED=false
fi

# Variables should be passed through to RUN commands
if echo "$ACTUAL" | grep -qE 'RUN nodejs--setup.sh \$\{?NODE_VERSION\}?'; then
    print_test_result "true" "$0" "023" "Variable substitution in setup nodejs"
else
    print_test_result "false" "$0" "023" "Variable substitution in setup nodejs"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qE 'RUN python--setup.sh \$\{?PYTHON_VERSION\}?'; then
    print_test_result "true" "$0" "023" "Variable substitution in setup python"
else
    print_test_result "false" "$0" "023" "Variable substitution in setup python"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
