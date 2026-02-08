#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: lifecycle name/port persistence and override behavior
#
# Documents behavior:
# - Name/port are persisted on the container and remain after stop/start.
# - start/restart do NOT accept --port override (new container settings only).
# - Port can be changed only by creating a new container (run again after remove).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="lifecycle-np-$RANDOM-$RANDOM"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
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

host_port_10000() {
  docker inspect -f '{{(index (index .HostConfig.PortBindings "10000/tcp") 0).HostPort}}' "$1" 2>/dev/null || true
}

state_of() {
  docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true
}

PORT_A="$(random_free_port)"
PORT_B="$(random_free_port)"

# 1) Create keep-alive container with explicit name/port.
if run_coding_booth --variant base --name "$NAME" --port "$PORT_A" --daemon --keep-alive -- 'sleep 60' >/dev/null 2>&1; then
  ACTUAL_PORT="$(host_port_10000 "$NAME")"
  if [[ "$ACTUAL_PORT" == "$PORT_A" ]]; then
    print_test_result "true" "$0" "1" "run keeps explicit name and UI port"
  else
    print_test_result "false" "$0" "1" "expected UI port $PORT_A but got '$ACTUAL_PORT'"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "run with explicit name/port should succeed"
  FAILED=$((FAILED + 1))
fi

# 2) stop/start keeps the same UI port.
if run_coding_booth stop --name "$NAME" >/dev/null 2>&1 \
  && run_coding_booth start --name "$NAME" --daemon >/dev/null 2>&1; then
  ACTUAL_PORT="$(host_port_10000 "$NAME")"
  if [[ "$ACTUAL_PORT" == "$PORT_A" ]]; then
    print_test_result "true" "$0" "2" "stop/start preserves container UI port"
  else
    print_test_result "false" "$0" "2" "expected preserved UI port $PORT_A but got '$ACTUAL_PORT'"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "stop/start should succeed"
  FAILED=$((FAILED + 1))
fi

# 3) start does not allow --port override.
set +e
START_PORT_OVERRIDE_OUTPUT="$(run_coding_booth start --name "$NAME" --port "$PORT_B" 2>&1)"
START_PORT_OVERRIDE_EXIT=$?
set -e

if [[ $START_PORT_OVERRIDE_EXIT -ne 0 ]] && grep -qi "flag provided but not defined\|unknown\|--port" <<<"$START_PORT_OVERRIDE_OUTPUT"; then
  print_test_result "true" "$0" "3" "start rejects --port override (documented behavior)"
else
  print_test_result "false" "$0" "3" "start should reject --port override"
  echo "  Output: $START_PORT_OVERRIDE_OUTPUT"
  FAILED=$((FAILED + 1))
fi

# 4) To change port, container must be recreated.
run_coding_booth stop --name "$NAME" >/dev/null 2>&1 || true
if ! run_coding_booth remove --name "$NAME" >/dev/null 2>&1; then
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
fi
if run_coding_booth --variant base --name "$NAME" --port "$PORT_B" --keep-alive -- 'sleep 1' >/dev/null 2>&1; then
  ACTUAL_PORT="$(host_port_10000 "$NAME")"
  if [[ "$ACTUAL_PORT" == "$PORT_B" ]] && [[ "$(state_of "$NAME")" == "exited" ]]; then
    print_test_result "true" "$0" "4" "recreate allows UI port override"
  else
    print_test_result "false" "$0" "4" "expected recreated container on port $PORT_B"
    echo "  Actual port: ${ACTUAL_PORT:-<empty>}"
    echo "  State: $(state_of "$NAME")"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "4" "recreate with new port should succeed"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
