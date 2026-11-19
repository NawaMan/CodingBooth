#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# Smoke test: verify pgvector and pg_trgm are actually enabled (not merely
# apt-installed) in the PostgREST example booth, and that PostgREST itself is
# installed. The deeper end-to-end proof — seeded data, both RPC endpoints,
# and reachability from the host through the published port — lives in
# tests/complex/test-boothfile-postgres-addons, which builds a dedicated named
# container instead of a one-off invocation.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)"

echo "=== Testing PostgreSQL Extensions + PostgREST Availability ==="
echo ""

output=$("$BOOTH" --variant base --port "${CB_PORT:-50721}" -- \
    'psql -d postgres -tAc "SELECT extname FROM pg_extension ORDER BY extname" && postgrest --version' 2>&1) || true

echo "$output"
echo ""

failed=0

if grep -qx 'pg_trgm' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} pg_trgm is enabled"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Expected pg_trgm to be enabled; got: $output"
    failed=1
fi

if grep -qx 'vector' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} pgvector is enabled as 'vector'"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Expected 'vector' (pgvector's CREATE EXTENSION name) to be enabled; got: $output"
    failed=1
fi

if grep -qiE 'PostgREST' <<< "$output"; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} PostgREST is installed"
else
    echo -e "${RED}\xe2\x9c\x97${NC} Expected PostgREST to be installed; got: $output"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}PostgreSQL extensions + PostgREST smoke test passed!${NC}"
else
    echo -e "${RED}PostgreSQL extensions + PostgREST smoke test FAILED!${NC}"
    exit 1
fi
