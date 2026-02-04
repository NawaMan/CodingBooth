#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: extra bind mount + extra port persistence across lifecycle
#
# Documents behavior:
# - Additional run args (-v bind and -p extra port) are part of container config.
# - stop/start preserves both bind mounts and port mappings.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="lifecycle-bp-$RANDOM-$RANDOM"
HOST_DIR="$(mktemp -d /tmp/cb-lifecycle-bind.XXXXXX)"
MARKER_FILE="$HOST_DIR/marker.txt"
echo "life-cycle-bind-ok" > "$MARKER_FILE"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$HOST_DIR"
}
trap cleanup EXIT

is_port_free() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  elif command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"
  else
    ! (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$port" >/dev/null 2>&1)
  fi
}

random_free_port() {
  local p
  for _ in {1..100}; do
    p=$((50000 + RANDOM % 10000))
    if is_port_free "$p"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

host_port() {
  local name="$1"
  local container_port="$2"
  docker inspect -f "{{(index (index .HostConfig.PortBindings \"${container_port}/tcp\") 0).HostPort}}" "$name" 2>/dev/null || true
}

has_bind() {
  local name="$1"
  local bind_prefix="$2"
  docker inspect -f '{{range .HostConfig.Binds}}{{println .}}{{end}}' "$name" 2>/dev/null | grep -q "^${bind_prefix}"
}

UI_PORT="$(random_free_port)"
EXTRA_PORT="$(random_free_port)"
BIND_ARG="${HOST_DIR}:/tmp/lifecycle-extra"

# 1) Create keep-alive booth with extra bind and extra port mapping.
if run_coding_booth --variant base --name "$NAME" --port "$UI_PORT" --daemon --keep-alive \
  -v "$BIND_ARG" -p "${EXTRA_PORT}:12345" -- 'sleep 60' >/dev/null 2>&1; then

  if [[ "$(host_port "$NAME" 10000)" == "$UI_PORT" ]] \
    && [[ "$(host_port "$NAME" 12345)" == "$EXTRA_PORT" ]] \
    && has_bind "$NAME" "$BIND_ARG"; then
    print_test_result "true" "$0" "1" "run stores extra bind and extra port mapping"
  else
    print_test_result "false" "$0" "1" "expected bind and both ports to be configured"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "run with extra bind/port should succeed"
  FAILED=$((FAILED + 1))
fi

# 2) Stop/start should preserve bind and extra port mapping.
if run_coding_booth stop --name "$NAME" >/dev/null 2>&1 \
  && run_coding_booth start --name "$NAME" --daemon >/dev/null 2>&1; then

  if [[ "$(host_port "$NAME" 10000)" == "$UI_PORT" ]] \
    && [[ "$(host_port "$NAME" 12345)" == "$EXTRA_PORT" ]] \
    && has_bind "$NAME" "$BIND_ARG"; then
    print_test_result "true" "$0" "2" "stop/start preserves bind and port mappings"
  else
    print_test_result "false" "$0" "2" "expected bind and ports to persist after restart"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "stop/start should succeed"
  FAILED=$((FAILED + 1))
fi

# 3) Bound content remains accessible after start.
if docker exec "$NAME" bash -lc 'test -f /tmp/lifecycle-extra/marker.txt' >/dev/null 2>&1; then
  print_test_result "true" "$0" "3" "bound directory remains mounted and readable"
else
  print_test_result "false" "$0" "3" "bound directory should remain mounted after start"
  FAILED=$((FAILED + 1))
fi

# cleanup through lifecycle command
if ! run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1; then
  print_test_result "false" "$0" "4" "remove --force should cleanup container"
  FAILED=$((FAILED + 1))
else
  print_test_result "true" "$0" "4" "remove --force cleans up lifecycle container"
fi

exit $FAILED
