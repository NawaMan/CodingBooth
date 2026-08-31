#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a booth can see, and reach, the host it runs on.
#
# A real service is started on the host (bound to 0.0.0.0, as a host service has
# to be for any container to reach it), then a booth is asked to dial it.
#
# Test 1: $BOOTH_HOST_NAME resolves from inside the booth. On Docker Desktop the
#         name comes for free; on native Linux it exists only because the booth
#         is started with --add-host host.docker.internal:host-gateway, which is
#         what this pins down.
# Test 2: the host's service actually answers on that name — the whole point:
#         a PostgREST (or anything else) on the host is usable from the booth.
# Test 3: $BOOTH_HOST_IP names the host, so a user or agent inside can read the
#         host's address off the environment (booth--info prints the same pair).
#
# Reaching the host *by that IP* is deliberately not asserted: it depends on the
# host's own firewall and on which interface the address belongs to, neither of
# which this feature controls. The name is the supported route and is asserted.
#
# tests/dryrun/dind/test003--dind-host-gateway.sh covers the shared-netns side of
# the same feature (alias on the sidecar, never on the booth) without docker run.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 is not available to stand up a host-side service"
    exit 0
fi

function generate_name() {
  local name
  while :; do
    name=$(printf "host-access-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

NAME="$(generate_name)"
HOST_PORT="$(pick_free_port)"
SERVE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cb-host-access.XXXXXX")"
SERVER_PID=""

function cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" >/dev/null 2>&1
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$SERVE_DIR"
  return 0
}
trap cleanup EXIT

# --- The host-side service ---------------------------------------------------
# Bound to 0.0.0.0: a 127.0.0.1-only bind is unreachable from any container, so
# a service bound that way would fail this test for a reason that is not booth's.
echo "ok" > "$SERVE_DIR/probe.txt"
# --directory rather than a `cd` subshell: $! must be the server itself, or
# cleanup kills the subshell and leaves the port held by an orphaned python.
python3 -m http.server "$HOST_PORT" --bind 0.0.0.0 --directory "$SERVE_DIR" >/dev/null 2>&1 &
SERVER_PID=$!
# Off the job table, so the kill in cleanup does not print "Terminated" over the
# test results.
disown "$SERVER_PID" 2>/dev/null || true

for _ in {1..20}; do
  if curl -fsS -m 2 -o /dev/null "http://127.0.0.1:${HOST_PORT}/probe.txt" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if ! curl -fsS -m 2 -o /dev/null "http://127.0.0.1:${HOST_PORT}/probe.txt" 2>/dev/null; then
  echo "SKIP: could not stand up a host service on port ${HOST_PORT}"
  exit 0
fi

# --- Ask a booth what it can see and reach -----------------------------------
# One booth run reports all three facts on marker lines, so a single container
# start covers the whole test.
PROBE='
  echo "CB-NAME=${BOOTH_HOST_NAME:-}"
  echo "CB-RESOLVED=$(getent hosts "${BOOTH_HOST_NAME:-none}" 2>/dev/null | awk "{print \$1; exit}")"
  echo "CB-CODE=$(curl -s -m 10 -o /dev/null -w "%{http_code}" "http://${BOOTH_HOST_NAME}:'"${HOST_PORT}"'/probe.txt")"
  echo "CB-IP=${BOOTH_HOST_IP:-}"
'

OUTPUT="$(run_coding_booth --variant base --name "$NAME" -- "$PROBE" 2>/dev/null || true)"

function marker() {
  echo "$OUTPUT" | grep "^$1=" | head -1 | cut -d= -f2- | tr -d '\r'
}

BOOTH_NAME_VALUE="$(marker CB-NAME)"
RESOLVED="$(marker CB-RESOLVED)"
CODE="$(marker CB-CODE)"
HOST_IP="$(marker CB-IP)"

# --- Test 1: the host has a name in here, and it resolves --------------------

if [[ "$BOOTH_NAME_VALUE" == "host.docker.internal" && -n "$RESOLVED" ]]; then
  print_test_result "true" "$0" "1" \
    "\$BOOTH_HOST_NAME ($BOOTH_NAME_VALUE) resolves to $RESOLVED inside the booth"
else
  print_test_result "false" "$0" "1" \
    "\$BOOTH_HOST_NAME should be host.docker.internal and resolve, got name='${BOOTH_NAME_VALUE:-<unset>}' resolved='${RESOLVED:-<none>}'"
  echo "Booth output:"
  echo "$OUTPUT"
  exit 1
fi

# --- Test 2: the host's service answers on that name -------------------------

if [[ "$CODE" == "200" ]]; then
  print_test_result "true" "$0" "2" \
    "A host service on port $HOST_PORT answers the booth at $BOOTH_NAME_VALUE"
else
  print_test_result "false" "$0" "2" \
    "Expected HTTP 200 from http://${BOOTH_NAME_VALUE}:${HOST_PORT}/probe.txt, got '${CODE:-<none>}'"
  echo "Booth output:"
  echo "$OUTPUT"
  exit 1
fi

# --- Test 3: the booth is told the host's own address ------------------------
# Unset is a legitimate answer only for a host with nothing but loopback, which
# a machine running this suite is not: it just served the request in test 2.

if [[ "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$HOST_IP" != 127.* ]]; then
  print_test_result "true" "$0" "3" "\$BOOTH_HOST_IP carries the host's address ($HOST_IP)"
else
  print_test_result "false" "$0" "3" \
    "\$BOOTH_HOST_IP should be a non-loopback IPv4 address, got '${HOST_IP:-<unset>}'"
  echo "Booth output:"
  echo "$OUTPUT"
  exit 1
fi
