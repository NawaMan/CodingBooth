#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: `booth build` turns a defaulted name into a valid Docker repository name.
#
# With no --name, build uses the project folder as the repository part of the image
# reference, and Docker refuses an uppercase repository ("repository name must be
# lowercase") before building anything. The run path never hit this: it puts the project
# name in the tag (codingbooth-local:<project>-...), where capitals are allowed.
# An explicit --name is the user's own choice and is passed through as typed.

PARENT=$(mktemp -d)
trap "rm -rf $PARENT" EXIT

TEST_DIR="$PARENT/NPQAA238"
mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'BOOTHFILE'
# syntax=codingbooth/boothfile:1
BOOTHFILE

ALL_PASSED=true

check() {
    local num="$1" desc="$2" pattern="$3"; shift 3
    local actual
    actual=$(run_coding_booth build --dryrun --code "$TEST_DIR" "$@" 2>/dev/null || true)
    if echo "$actual" | grep -qE -- "$pattern"; then
        print_test_result "true" "$0" "$num" "$desc"
    else
        print_test_result "false" "$0" "$num" "$desc"
        echo "Actual output:"
        echo "$actual"
        ALL_PASSED=false
    fi
}

check 001 "uppercase folder name defaults to a lowercase repository" \
    "-t npqaa238:[0-9a-f]+( |$)"

check 002 "explicit --name is used as typed" \
    "-t KeepMe:[0-9a-f]+( |$)" --name KeepMe

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
