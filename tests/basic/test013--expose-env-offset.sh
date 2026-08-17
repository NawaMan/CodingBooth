#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a host-env expose port may fall back to a base-relative +OFFSET.
#
#   run-args = ["--publish", "${SERVER_PORT:-+300}:9999"]
#
# When SERVER_PORT is unset, shellexpand (at TOML unmarshal) resolves the
# expression to "+300", and ResolveRelativePorts then rewrites it to
# offsetBase + 300.
#
# Test 1: no offset-base — the base is the booth's own port, so a booth on port P
#         publishes container port 9999 on the host at P + 300. A default that
#         follows the booth port, with no fixed number baked into the config:
#         this is what makes ${SERVER_PORT:-+300} end up as 10300 on a booth on
#         10000.
# Test 2: offset-base set — the fallback counts from the base instead, and the
#         booth port stops deciding it. Asserted as "lands on base + 300" AND
#         "is not boothPort + 300", since the two are what this separates.
#
# Both are asserted against a running container's real docker port bindings.
# tests/dryrun/test030--offset-base.sh covers the same ground without docker.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

OFFSET=300
CONTAINER_PORT=9999

function generate_name() {
  local name
  while :; do
    name=$(printf "expose-offset-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

function is_port_free() {
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$p" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  elif command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$p )" 2>/dev/null | grep -q ":$p"
  else
    ! (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$p" >/dev/null 2>&1)
  fi
}

# A base port whose booth port AND its +OFFSET published port are both free, so
# neither the booth itself nor the offset mapping collides with something else.
function base_port_with_free_offset() {
  local port i
  for i in {1..100}; do
    port=$((50000 + RANDOM % 10001))
    if is_port_free "$port" && is_port_free $((port + OFFSET)); then
      echo "$port"
      return 0
    fi
  done
  echo "Failed to find a free base port whose +$OFFSET is also free" >&2
  return 1
}

# An offset base for a booth already sitting on $1. Its +OFFSET port must be
# free, must not be the booth's own port (booth refuses to publish over it), and
# must differ from what the booth port would have produced — otherwise test 2
# cannot tell a moved base from the default one.
function offset_base_away_from_booth_port() {
  local booth_port="$1" base i
  for i in {1..100}; do
    base=$((30000 + RANDOM % 10001))
    if [[ "$base" != "$booth_port" ]] \
       && [[ $((base + OFFSET)) != "$booth_port" ]] \
       && is_port_free $((base + OFFSET)); then
      echo "$base"
      return 0
    fi
  done
  echo "Failed to find an offset base whose +$OFFSET is free" >&2
  return 1
}

# Start a booth from $2 named $1, wait for the container, and echo the host port
# docker bound to CONTAINER_PORT (empty if it never came up or never bound).
function published_host_port() {
  local name="$1" config="$2" i

  run_coding_booth --config "$config" --name "$name" -- sleep 30 &

  # --- Wait for the container to appear (max ~30 seconds) ---
  for i in {1..30}; do
    if docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! docker inspect "$name" >/dev/null 2>&1; then
    return 0
  fi

  docker inspect \
    -f "{{(index (index .NetworkSettings.Ports \"${CONTAINER_PORT}/tcp\") 0).HostPort}}" \
    "$name" 2>/dev/null || true
}

NAME="$(generate_name)"
PORT="$(base_port_with_free_offset)"
EXPECTED=$((PORT + OFFSET))
CONFIG="test013--tmp-${NAME}.toml"

NAME2="$(generate_name)"
CONFIG2="test013--tmp-${NAME2}.toml"

# The fallback is only used when the variable is unset — make sure it is.
unset SERVER_PORT

function cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker rm -f "$NAME2" >/dev/null 2>&1 || true
  rm -f "$CONFIG" "$CONFIG2"
}
trap cleanup EXIT

# --- Test 1: no offset-base — the fallback follows the booth port -------------

printf 'variant = "base"\nport = "%s"\nrun-args = ["--publish", "${SERVER_PORT:-+%s}:%s"]\n' \
  "$PORT" "$OFFSET" "$CONTAINER_PORT" > "$CONFIG"

HOST_PORT="$(published_host_port "$NAME" "$CONFIG")"

if [[ -z "$HOST_PORT" ]]; then
  print_test_result "false" "$0" "1" "Container '$NAME' should start with a host-env offset expose"
  exit 1
fi

# The host port bound to CONTAINER_PORT must be booth port + OFFSET.
if [[ "$HOST_PORT" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" \
    "\${SERVER_PORT:-+$OFFSET} on booth port $PORT publishes $CONTAINER_PORT on host $EXPECTED"
else
  print_test_result "false" "$0" "1" \
    "Expected host port $EXPECTED for container $CONTAINER_PORT, got '${HOST_PORT:-<none>}'"
  exit 1
fi

# Free the first booth's ports before the second one picks its own.
docker rm -f "$NAME" >/dev/null 2>&1 || true

# --- Test 2: offset-base set — the fallback follows the base instead ----------

PORT2="$(base_port_with_free_offset)"
BASE2="$(offset_base_away_from_booth_port "$PORT2")"
EXPECTED2=$((BASE2 + OFFSET))
NOT_EXPECTED2=$((PORT2 + OFFSET))

printf 'variant = "base"\nport = "%s"\noffset-base = "%s"\nrun-args = ["--publish", "${SERVER_PORT:-+%s}:%s"]\n' \
  "$PORT2" "$BASE2" "$OFFSET" "$CONTAINER_PORT" > "$CONFIG2"

HOST_PORT2="$(published_host_port "$NAME2" "$CONFIG2")"

if [[ -z "$HOST_PORT2" ]]; then
  print_test_result "false" "$0" "2" "Container '$NAME2' should start with an offset-base of $BASE2"
  exit 1
fi

if [[ "$HOST_PORT2" == "$EXPECTED2" && "$HOST_PORT2" != "$NOT_EXPECTED2" ]]; then
  print_test_result "true" "$0" "2" \
    "offset-base $BASE2 on booth port $PORT2 publishes $CONTAINER_PORT on host $EXPECTED2, not $NOT_EXPECTED2"
else
  print_test_result "false" "$0" "2" \
    "Expected host port $EXPECTED2 (offset base $BASE2, not booth port $PORT2), got '${HOST_PORT2:-<none>}'"
  exit 1
fi
