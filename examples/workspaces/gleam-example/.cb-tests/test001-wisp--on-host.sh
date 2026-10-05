#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Full integration test run from the host: start the booth, run the in-booth suite,
# then check the Wisp server is reachable from the host through the published port.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
source "$REPO_ROOT/tests/booth-bin--source.sh"
BOOTH="$(resolve_booth_bin)" || { echo "no booth found under $REPO_ROOT" >&2; exit 1; }

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

CONTAINER_NAME="gleam-example"
BOOTH_PORT="${CB_PORT:-50391}"
# config.toml publishes +8000:8000 — relative to the booth port. Use that mapping as
# shipped (no -p here), so the test proves what a user gets.
SERVER_HOST_PORT=$((BOOTH_PORT + 8000))

cleanup() {
    echo
    echo "Cleaning up..."
    docker exec "$CONTAINER_NAME" bash -c "cd /home/coder/code && just stop" >/dev/null 2>&1 || true
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Testing gleam-example ==="
cleanup

"$BOOTH" --no-browser --port "$BOOTH_PORT" --daemon --name "$CONTAINER_NAME" || true
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
docker exec -u coder "$CONTAINER_NAME" bash -lc "cd /home/coder/code && just start" || fail "just start failed"

RESPONSE="$(curl -s --max-time 5 "http://localhost:${SERVER_HOST_PORT}/greet/host" || true)"
if [[ "$RESPONSE" == *'"Hello, host!"'* ]]; then
    pass "Wisp server reachable from host at port ${SERVER_HOST_PORT}"
else
    echo "  Response: ${RESPONSE:-<empty>}"
    docker exec "$CONTAINER_NAME" cat /tmp/gleam-example.log 2>/dev/null | tail -20 || true
    docker port "$CONTAINER_NAME" 2>/dev/null || true
    fail "Wisp server should be reachable from host"
fi

docker exec -u coder "$CONTAINER_NAME" bash -lc "cd /home/coder/code && just stop" >/dev/null 2>&1
sleep 1
if curl -s --max-time 3 "http://localhost:${SERVER_HOST_PORT}/" >/dev/null 2>&1; then
    fail "Server should not be reachable after just stop"
fi
pass "Server not reachable after stop (expected)"

echo
echo -e "${GREEN}All tests passed!${NC}"
