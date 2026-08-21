#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Verify /__booth/health and /__booth/info endpoints are served by the
# wrapper nginx (codeserver variant exercises the same template used by
# desktop-xfce / desktop-kde / notebook).

set -euo pipefail

source ../common--source.sh

NAME="health-test-$RANDOM"
PORT=""
LOG="$0.log"

# Scratch files for curl's response bodies. Honour TMPDIR rather than writing to
# /tmp by name: where /tmp is not writable (a sandboxed shell, a hardened CI
# image) curl still *fetches* the page and still prints its status through -w,
# but exits 23 on the failed write. The `|| echo "000"` below then appends to a
# status that is already on stdout — "200" becomes "200000", every probe misses,
# and a perfectly healthy booth times out after 90s.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cb-booth-health.XXXXXX")"
HEALTH_FILE="$TMP_DIR/health"
INFO_FILE="$TMP_DIR/info"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

is_port_free() {
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$p" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  elif command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$p )" 2>/dev/null | grep -q ":$p"
  else
    ! (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$p" >/dev/null 2>&1)
  fi
}

random_free_port() {
  local port i
  for i in {1..100}; do
    port=$((50000 + RANDOM % 10001))
    if is_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done
  echo "Failed to find free port" >&2
  return 1
}

PORT="$(random_free_port)"

# Start the codeserver variant in daemon mode (keeps default CMD = start-codeserver-wrapped)
run_coding_booth --variant codeserver --name "$NAME" --port "$PORT" --daemon \
  > "$LOG" 2>&1 || true

# Wait for the wrapper nginx + inner code-server to be healthy (max ~90s)
HEALTH_URL="http://127.0.0.1:$PORT/__booth/health"
INFO_URL="http://127.0.0.1:$PORT/__booth/info"

HEALTH_BODY=""
HEALTH_CODE=""
RESP=""
for i in {1..90}; do
  RESP=$(curl -s -o "$HEALTH_FILE" -w '%{http_code}' --max-time 4 "$HEALTH_URL" 2>/dev/null || echo "000")
  if [[ "$RESP" == "200" ]]; then
    HEALTH_CODE="$RESP"
    HEALTH_BODY=$(cat "$HEALTH_FILE")
    break
  fi
  sleep 1
done

# Test 1: /__booth/health returns 200
if [[ "$HEALTH_CODE" == "200" ]]; then
  print_test_result "true" "$0" "1" "/__booth/health returned 200 on port $PORT"
else
  # Report the last response, not HEALTH_CODE — that is only ever assigned on
  # success, so it printed an empty "last=" on exactly the runs that needed it.
  print_test_result "false" "$0" "1" "/__booth/health did not reach 200 within timeout (last=$RESP)"
  exit 1
fi

# Test 2: body starts with "ok " and contains a timestamp
if [[ "$HEALTH_BODY" =~ ^ok\ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
  print_test_result "true" "$0" "2" "/__booth/health body is 'ok <iso8601>' ($HEALTH_BODY)"
else
  print_test_result "false" "$0" "2" "/__booth/health body malformed: '$HEALTH_BODY'"
  exit 1
fi

# Test 3: /__booth/info returns 200 JSON
INFO_CODE=$(curl -s -o "$INFO_FILE" -w '%{http_code}' --max-time 4 "$INFO_URL" 2>/dev/null || echo "000")
INFO_BODY=$(cat "$INFO_FILE" 2>/dev/null || echo "")

if [[ "$INFO_CODE" == "200" ]]; then
  print_test_result "true" "$0" "3" "/__booth/info returned 200"
else
  print_test_result "false" "$0" "3" "/__booth/info expected 200, got $INFO_CODE"
  exit 1
fi

# Test 4: info payload carries variant + port
if [[ "$INFO_BODY" == *'"variant":"codeserver"'* && "$INFO_BODY" == *"\"port\":\"$PORT\""* ]]; then
  print_test_result "true" "$0" "4" "/__booth/info payload has variant+port: $INFO_BODY"
else
  print_test_result "false" "$0" "4" "/__booth/info payload missing variant/port: $INFO_BODY"
  exit 1
fi
