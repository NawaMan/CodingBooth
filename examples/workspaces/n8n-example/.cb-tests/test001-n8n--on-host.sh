#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Start the booth, confirm n8n is healthy inside, then curl the published
# host port. +expose publishes 21200:21200 literally, not relative to the
# booth port. The in-booth test leaves the server running for that curl.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)" || { echo "no booth found under $REPO_ROOT" >&2; exit 1; }

cd "$(dirname "$0")/.."

export CB_BROWSER=false

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

CONTAINER_NAME="n8n-example"
BOOTH_PORT="${CB_PORT:-50422}"
N8N_HOST_PORT=21200

# booth stop/remove also take down the DinD sidecar that +sandbox brings.
cleanup() {
    echo
    echo "Cleaning up..."
    "$BOOTH" stop --name "$CONTAINER_NAME" --force >/dev/null 2>&1 || true
    "$BOOTH" remove --name "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker network rm "${CONTAINER_NAME}-${BOOTH_PORT}-net" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Testing n8n-example ==="
cleanup

# --dind-allowed: +sandbox sets dind = true, which otherwise stops for a [y/N]
# consent prompt on /dev/tty (see docs/BOOTH_SECURITY.md) -- silent in a script.
"$BOOTH" --dind-allowed --no-browser --port "$BOOTH_PORT" --daemon --name "$CONTAINER_NAME" || true
sleep 2
grep -q "^${CONTAINER_NAME}$" <<< "$(docker ps --format '{{.Names}}')" || fail "Failed to start booth"
pass "Booth started"

echo
echo "Running in-booth tests..."
if ! docker exec -u coder "$CONTAINER_NAME" bash -lc "cd /home/coder/code && ./.cb-tests/inBooth--run-all-tests.sh" 2>&1 | tee "$0.out"; then
    fail "In-booth tests failed"
fi
pass "In-booth tests passed"

echo
echo "=== Testing host accessibility ==="
RESPONSE="$(curl -fsS --max-time 10 "http://localhost:${N8N_HOST_PORT}/healthz" || true)"
if echo "$RESPONSE" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    pass "n8n reachable from host at port ${N8N_HOST_PORT}"
else
    echo "  Response: ${RESPONSE:-<empty>}"
    docker exec "$CONTAINER_NAME" cat /tmp/n8n.log 2>/dev/null | tail -30 || true
    docker port "$CONTAINER_NAME" 2>/dev/null || true
    fail "n8n should be reachable from the host"
fi

echo
echo -e "${GREEN}All tests passed!${NC}"
