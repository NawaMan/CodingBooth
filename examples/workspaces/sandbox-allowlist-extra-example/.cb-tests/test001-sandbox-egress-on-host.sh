#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "=== test001: sandbox allowlist + extra (non-DinD) ==="

if ../../../codingbooth --variant base --version latest --port "${CB_PORT:-50281}" --name sandbox-allowlist-extra-example --sandboxed -- ./.cb-tests/test-on-container.sh; then
    pass "Sandbox non-DinD test passed"
else
    fail "Sandbox non-DinD test failed"
fi
