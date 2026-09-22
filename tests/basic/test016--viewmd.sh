#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -uo pipefail

source ../common--source.sh

# -------------------------------------------------------
# Test: viewmd (MarkDownViewer) ships in the base image
#
# viewmd is installed by variants/base/setups/viewmd--setup.sh from the
# Dockerfile, so every variant inherits it. It is also advertised in the login
# welcome message — a tool nobody is told about is a tool nobody uses, so the
# welcome line is guarded here too. The Console UI does not start it; a
# daemon booth must have nothing on :8765 until the user runs viewmd.
#
# Deliberately NOT `set -e`: a booth that fails to start makes every capture
# below empty, and under `set -e` the script would die on the first one having
# printed nothing at all — no failing assertion, no output, nothing to debug
# from. Each check reports what it actually got instead.
# -------------------------------------------------------

FAILED=0

# -------------------------------------------------------
# Test 1: viewmd is on PATH
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'command -v viewmd' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "/usr/local/bin/viewmd" ]]; then
  print_test_result "true" "$0" "1" "viewmd is installed in the base image"
else
  print_test_result "false" "$0" "1" "viewmd is installed in the base image"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  echo "  Hint: the base image must carry viewmd. If a locally-built image has"
  echo "        taken the ${CB_PREBUILD_REPO:-nawaman/codingbooth} tag, re-pull it."
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: viewmd runs and reports a version
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'viewmd version' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  print_test_result "true" "$0" "2" "viewmd reports a version ($ACTUAL)"
else
  print_test_result "false" "$0" "2" "viewmd reports a version"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: the welcome message lists viewmd
#
# The welcome only prints for an interactive login shell, and the outer
# `bash -lc` booth runs commands with is not interactive — so it never sets
# TIP_SHOWN and the inner `bash -lic` prints the banner.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- 'bash -lic true 2>/dev/null | grep -c "^  viewmd "' 2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "3" "welcome message lists viewmd"
else
  print_test_result "false" "$0" "3" "welcome message lists viewmd"
  echo "  Matching welcome lines: ${ACTUAL:-<empty — the booth did not run>} (want 1)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 4: viewmd actually serves Markdown
#
# --version proves the file is executable; this proves it works. Serves the
# in-image docs folder, then stops the daemon again.
# -------------------------------------------------------
ACTUAL=$(run_coding_booth --variant base -- \
  'viewmd --folder /opt/codingbooth/docs --daemon >/dev/null 2>&1; curl -fsS -o /dev/null -w "SERVE=%{http_code}\n" http://127.0.0.1:8765/ || echo SERVE=FAILED; viewmd stop >/dev/null 2>&1' \
  2>&1 | tail -1) || ACTUAL=""

if [[ "$ACTUAL" == "SERVE=200" ]]; then
  print_test_result "true" "$0" "4" "viewmd serves a folder of Markdown files"
else
  print_test_result "false" "$0" "4" "viewmd serves a folder of Markdown files"
  echo "  Actual output: ${ACTUAL:-<empty — the booth did not run>}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 5: the Console UI does not start viewmd on boot. The document icon
# starts it on demand via POST /booth-messages/api/viewmd.
# -------------------------------------------------------
NAME="viewmd-noauto-$RANDOM"
PORT="$(pick_free_port)"
cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_200() {
  local url="$1"
  for i in {1..40}; do
    if curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q 200; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_coding_booth --variant base --name "$NAME" --port "$PORT" --daemon > "$0.log" 2>&1

if ! wait_for_200 "http://127.0.0.1:${PORT}/__booth/health"; then
  print_test_result "false" "$0" "5" "Booth '$NAME' never answered /__booth/health"
  docker logs "$NAME" 2>&1 | tail -20 >&2
  exit 1
fi

STARTED=$(docker logs "$NAME" 2>&1 | grep -c 'viewmd .* running in background' || true)
HTTP=$(docker exec "$NAME" sh -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:8765/ || true')

if [[ "$STARTED" == "0" && "$HTTP" != "200" ]]; then
  print_test_result "true" "$0" "5" "Console UI does not autostart viewmd"
else
  print_test_result "false" "$0" "5" "Console UI should not autostart viewmd"
  echo "  background-start log lines: $STARTED (want 0)"
  echo "  http://127.0.0.1:8765 inside the booth: $HTTP (want not 200)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 6: the document icon's API starts viewmd --daemon
# -------------------------------------------------------
POST_CODE=""
for i in {1..20}; do
  POST_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/booth-messages/api/viewmd")
  [[ "$POST_CODE" == "200" ]] && break
  sleep 0.5
done
HTTP=$(docker exec "$NAME" sh -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:8765/ || true')

if [[ "$POST_CODE" == "200" && "$HTTP" == "200" ]]; then
  print_test_result "true" "$0" "6" "POST /booth-messages/api/viewmd starts viewmd --daemon"
else
  print_test_result "false" "$0" "6" "POST /booth-messages/api/viewmd should start viewmd --daemon"
  echo "  POST status: $POST_CODE (want 200)"
  echo "  http://127.0.0.1:8765 inside the booth: $HTTP (want 200)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 7: a second POST is a no-op, not a second daemon
# -------------------------------------------------------
POST2=$(curl -s -o /tmp/viewmd-api-body.json -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/booth-messages/api/viewmd")
BODY2=$(cat /tmp/viewmd-api-body.json 2>/dev/null || true)
rm -f /tmp/viewmd-api-body.json

if [[ "$POST2" == "200" && "$BODY2" == *'"running":true'* ]]; then
  print_test_result "true" "$0" "7" "A second POST /booth-messages/api/viewmd is a no-op"
else
  print_test_result "false" "$0" "7" "A second POST /booth-messages/api/viewmd should report already running"
  echo "  POST status: $POST2 (want 200)"
  echo "  body: $BODY2"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 8: the document icon tooltip names the Markdown viewer
# -------------------------------------------------------
PAGE=$(curl -s --compressed "http://127.0.0.1:${PORT}/")
if [[ "$PAGE" == *'title="Markdown viewer"'* ]]; then
  print_test_result "true" "$0" "8" "document icon tooltip is Markdown viewer"
else
  print_test_result "false" "$0" "8" "document icon tooltip should be Markdown viewer"
  echo "  First 200 chars: ${PAGE:0:200}"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
