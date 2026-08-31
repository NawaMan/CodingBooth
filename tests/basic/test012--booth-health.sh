#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Verify /__booth/health and /__booth/info endpoints are served by the
# wrapper nginx (codeserver variant exercises the same template used by
# desktop-xfce / desktop-kde / notebook), and that the terminal variant serves
# /__booth/health from its own template.

set -euo pipefail

source ../common--source.sh

NAME="health-test-$RANDOM"
BASE_NAME="health-base-$RANDOM"
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
  docker stop "$BASE_NAME" >/dev/null 2>&1 || true
  docker rm -f "$BASE_NAME" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

PORT="$(pick_free_port)"

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

# --- The terminal variant serves the endpoint from its own template ----------
#
# It has no inner web service to wrap, so it probes session 1's ttyd instead.
# This is what `booth run` waits on before opening a browser: the terminal UI's
# root is a static file nginx serves the moment it binds, whether or not ttyd
# behind it is listening yet.
# Distinct from $PORT: the codeserver booth above is still running — the
# trap removes it at exit, not here — so a shared port fails to bind.
BASE_PORT="$(pick_free_port_other_than "$PORT")"
run_coding_booth --variant base --name "$BASE_NAME" --port "$BASE_PORT" --daemon \
  >> "$LOG" 2>&1 || true

BASE_HEALTH_URL="http://127.0.0.1:$BASE_PORT/__booth/health"
BASE_BODY=""
BASE_CODE=""
BASE_RESP=""
for i in {1..90}; do
  BASE_RESP=$(curl -s -o "$HEALTH_FILE" -w '%{http_code}' --max-time 4 "$BASE_HEALTH_URL" 2>/dev/null || echo "000")
  if [[ "$BASE_RESP" == "200" ]]; then
    BASE_CODE="$BASE_RESP"
    BASE_BODY=$(cat "$HEALTH_FILE")
    break
  fi
  sleep 1
done

# Test 5: the terminal variant answers on the same endpoint
if [[ "$BASE_CODE" == "200" ]]; then
  print_test_result "true" "$0" "5" "/__booth/health returned 200 on the base variant (port $BASE_PORT)"
else
  print_test_result "false" "$0" "5" "/__booth/health did not reach 200 on the base variant (last=$BASE_RESP)"
  exit 1
fi

# Test 6: the answer came from the endpoint, not from the page behind it.
#
# The failure this guards is quiet: point the probe at ttyd's own '/s1/' and it
# answers 200, which error_page cannot intercept, so nginx returns the whole
# 700 KB terminal page as the health response. It still looks "healthy" to any
# caller checking only the status — so check the body.
if [[ "$BASE_BODY" =~ ^ok\ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
  print_test_result "true" "$0" "6" "base /__booth/health body is 'ok <iso8601>' ($BASE_BODY)"
else
  print_test_result "false" "$0" "6" "base /__booth/health body malformed (${#BASE_BODY} bytes): '${BASE_BODY:0:80}'"
  exit 1
fi
# Every capture below ends in `|| true`. Under `set -euo pipefail` a failing
# pipeline inside an assignment ends the script rather than letting the case
# report what it saw — curl exits 56 while a replacement booth's port is not
# listening yet, and grep exits 1 when the page carries no id. Both are states
# these cases exist to catch, not reasons to stop.
#
# Test 7: the response identifies which booth answered.
#
# Ports get reused, and the browser hands a reused URL to a tab that is already
# open. This header is how that tab tells the booth that served it from whoever
# is on the port now; without it a page from a base booth happily drives a
# notebook booth. It must also match what the page was rendered with.
BASE_INSTANCE=$(curl -s -D - -o /dev/null --max-time 4 "$BASE_HEALTH_URL" 2>/dev/null \
  | tr -d '\r' | awk 'tolower($1) == "x-booth-instance:" { print $2 }' || true)
BASE_PAGE_INSTANCE=$(curl -s --max-time 4 "http://127.0.0.1:$BASE_PORT/" 2>/dev/null \
  | grep -o 'window.BOOTH_INSTANCE_ID="[0-9a-f]*"' | head -1 | grep -o '[0-9a-f]\{16,\}' || true)

if [[ "$BASE_INSTANCE" =~ ^[0-9a-f]{16,}$ && "$BASE_INSTANCE" == "$BASE_PAGE_INSTANCE" ]]; then
  print_test_result "true" "$0" "7" "X-Booth-Instance matches the id baked into the page ($BASE_INSTANCE)"
else
  print_test_result "false" "$0" "7" "X-Booth-Instance '$BASE_INSTANCE' does not match the page's '$BASE_PAGE_INSTANCE'"
  exit 1
fi

# Test 8: two booths are two identities.
#
# If a restart or a replacement reused the id, a stale tab could not tell it had
# been swapped — which is the whole point of the header.
docker rm -f "$BASE_NAME" >/dev/null 2>&1 || true
run_coding_booth --variant base --name "$BASE_NAME" --port "$BASE_PORT" --daemon \
  >> "$LOG" 2>&1 || true
SECOND_INSTANCE=""
for i in {1..90}; do
  SECOND_INSTANCE=$(curl -s -D - -o /dev/null --max-time 4 "$BASE_HEALTH_URL" 2>/dev/null \
    | tr -d '\r' | awk 'tolower($1) == "x-booth-instance:" { print $2 }' || true)
  # `if`, not `&& break`: under `set -e` a bare failing test on the last line of
  # the loop body ends the script rather than the iteration, which silently
  # skipped this whole case.
  if [[ "$SECOND_INSTANCE" =~ ^[0-9a-f]{16,}$ ]]; then
    break
  fi
  sleep 1
done

if [[ "$SECOND_INSTANCE" =~ ^[0-9a-f]{16,}$ && "$SECOND_INSTANCE" != "$BASE_INSTANCE" ]]; then
  print_test_result "true" "$0" "8" "A replacement booth on the same port has its own id ($SECOND_INSTANCE)"
else
  print_test_result "false" "$0" "8" "Replacement booth reported id '$SECOND_INSTANCE', previous was '$BASE_INSTANCE'"
  exit 1
fi
