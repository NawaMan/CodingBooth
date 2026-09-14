#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

# Locate the booth wrapper from this script's own location, so it works from any cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
BOOTH="$REPO_ROOT/booth"
[ -x "$BOOTH" ] || BOOTH="$REPO_ROOT/codingbooth"
[ -x "$BOOTH" ] || { echo "booth wrapper not found under $REPO_ROOT" >&2; exit 1; }

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "=== test001: egress allowlist + extra (non-DinD) ==="

if "$BOOTH" --variant base --version latest --port "${CB_PORT:-50281}" --name egress-allowlist-extra-example --egress -- ./.cb-tests/test-on-container.sh; then
    pass "Egress non-DinD test passed"
else
    fail "Egress non-DinD test failed"
fi
