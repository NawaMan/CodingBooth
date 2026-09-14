#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

# Test: `install pg-ext` and `setup postgrest` compile to the right RUN lines
#
# pg-ext-pkg emits `install pg-ext ${PG_EXTS}`, which must compile to
# `RUN pg-ext--install.sh <names>` — the generic install-directive compiler,
# unchanged, dispatching to the new pg-ext--install.sh script by name. The
# postgrest template emits `setup postgrest --version ${VER}`, which must
# compile the same way every other setup does: `RUN postgrest--setup.sh --version <ver>`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

mkdir -p "$TEST_DIR/.booth"
cat > "$TEST_DIR/.booth/Boothfile" << 'EOF'
# syntax=codingbooth/boothfile:1

setup postgresql --version 16
install pg-ext pgvector,pg_trgm
setup postgrest --version 16.2
EOF

ACTUAL=$(run_coding_booth emit-dockerfile --code "$TEST_DIR" 2>/dev/null)

ALL_PASSED=true

if echo "$ACTUAL" | grep -qF "RUN postgresql--setup.sh --version 16"; then
    print_test_result "true" "$0" "032a" "setup postgresql compiles to postgresql--setup.sh"
else
    print_test_result "false" "$0" "032a" "setup postgresql compiles to postgresql--setup.sh"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "RUN pg-ext--install.sh pgvector,pg_trgm"; then
    print_test_result "true" "$0" "032b" "install pg-ext compiles to pg-ext--install.sh with the package list intact"
else
    print_test_result "false" "$0" "032b" "install pg-ext compiles to pg-ext--install.sh with the package list intact"
    ALL_PASSED=false
fi

if echo "$ACTUAL" | grep -qF "RUN postgrest--setup.sh --version 16.2"; then
    print_test_result "true" "$0" "032c" "setup postgrest compiles to postgrest--setup.sh"
else
    print_test_result "false" "$0" "032c" "setup postgrest compiles to postgrest--setup.sh"
    ALL_PASSED=false
fi

# The three RUN lines must appear in Boothfile order (postgresql, then pg-ext,
# then postgrest) — this Boothfile is hand-written, so there is no segment-order
# band or alphabetical tiebreak to rely on; the compiler must preserve line order.
POSTGRESQL_POS=$(echo "$ACTUAL" | grep -n "RUN postgresql--setup.sh" | head -1 | cut -d: -f1)
PG_EXT_POS=$(echo "$ACTUAL" | grep -n "RUN pg-ext--install.sh" | head -1 | cut -d: -f1)
POSTGREST_POS=$(echo "$ACTUAL" | grep -n "RUN postgrest--setup.sh" | head -1 | cut -d: -f1)

if [[ -n "$POSTGRESQL_POS" && -n "$PG_EXT_POS" && -n "$POSTGREST_POS" ]] \
   && (( POSTGRESQL_POS < PG_EXT_POS && PG_EXT_POS < POSTGREST_POS )); then
    print_test_result "true" "$0" "032d" "RUN lines preserve Boothfile order: postgresql, pg-ext, postgrest"
else
    print_test_result "false" "$0" "032d" "RUN lines preserve Boothfile order: postgresql, pg-ext, postgrest"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    echo "Actual output:"
    echo "$ACTUAL"
    exit 1
fi
