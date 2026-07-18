#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a host-env expose port may fall back to a booth-relative +OFFSET.
#
#   run-args = ["--publish", "${SERVER_PORT:-+300}:9999"]
#
# When SERVER_PORT is unset, shellexpand (at TOML unmarshal) resolves the
# expression to "+300", and ResolveRelativePorts then rewrites it to
# boothPort + 300. So a booth on port P publishes container port 9999 on the
# host at P + 300 — a default that follows the booth port, no fixed number baked
# into the config. This is what makes ${SERVER_PORT:-+300} end up as 10300 for a
# booth on 10000.
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

NAME="$(generate_name)"
PORT="$(base_port_with_free_offset)"
EXPECTED=$((PORT + OFFSET))
CONFIG="test013--tmp-${NAME}.toml"

# The fallback is only used when the variable is unset — make sure it is.
unset SERVER_PORT

function cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -f "$CONFIG"
}
trap cleanup EXIT

printf 'variant = "base"\nport = "%s"\nrun-args = ["--publish", "${SERVER_PORT:-+%s}:%s"]\n' \
  "$PORT" "$OFFSET" "$CONTAINER_PORT" > "$CONFIG"

run_coding_booth --config "$CONFIG" --name "$NAME" -- sleep 30 &

# --- Wait for the container to appear (max ~30 seconds) ---
for i in {1..30}; do
  if docker inspect "$NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "false" "$0" "1" "Container '$NAME' should start with a host-env offset expose"
  exit 1
fi

# The host port bound to CONTAINER_PORT must be booth port + OFFSET.
HOST_PORT=$(docker inspect \
  -f "{{(index (index .NetworkSettings.Ports \"${CONTAINER_PORT}/tcp\") 0).HostPort}}" \
  "$NAME" 2>/dev/null || true)

if [[ "$HOST_PORT" == "$EXPECTED" ]]; then
  print_test_result "true" "$0" "1" \
    "\${SERVER_PORT:-+$OFFSET} on booth port $PORT publishes $CONTAINER_PORT on host $EXPECTED"
else
  print_test_result "false" "$0" "1" \
    "Expected host port $EXPECTED for container $CONTAINER_PORT, got '${HOST_PORT:-<none>}'"
  exit 1
fi
