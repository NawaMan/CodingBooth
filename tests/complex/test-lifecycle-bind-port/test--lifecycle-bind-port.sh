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
HOST_DIR="$(mktemp -d "${SCRIPT_DIR}/.cb-lifecycle-bind.XXXXXX")"
MARKER_FILE="$HOST_DIR/marker.txt"
echo "life-cycle-bind-ok" > "$MARKER_FILE"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$HOST_DIR"
}
trap cleanup EXIT

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

# Both are published on the same container (--port UI_PORT, -p EXTRA_PORT:12345),
# so they have to differ or docker is asked to bind one host port twice.
UI_PORT="$(pick_free_port)"
EXTRA_PORT="$(pick_free_port_other_than "$UI_PORT")"
BIND_ARG="${HOST_DIR}:/tmp/lifecycle-extra"

diag() { sed 's/^/    /' >&2; }

# 1) Create keep-alive booth with extra bind and extra port mapping.
RUN_LOG=$(mktemp)
if run_coding_booth --variant base --name "$NAME" --port "$UI_PORT" --daemon --keep-alive \
  -v "$BIND_ARG" -p "${EXTRA_PORT}:12345" -- 'sleep 120' >"$RUN_LOG" 2>&1; then

  if [[ "$(host_port "$NAME" 10000)" == "$UI_PORT" ]] \
    && [[ "$(host_port "$NAME" 12345)" == "$EXTRA_PORT" ]] \
    && has_bind "$NAME" "$BIND_ARG"; then
    print_test_result "true" "$0" "1" "run stores extra bind and extra port mapping"
  else
    print_test_result "false" "$0" "1" "expected bind and both ports to be configured"
    {
      echo "DIAG test 1: container created but config mismatch"
      echo "  expected UI_PORT=$UI_PORT, got $(host_port "$NAME" 10000)"
      echo "  expected EXTRA_PORT=$EXTRA_PORT for 12345/tcp, got $(host_port "$NAME" 12345)"
      echo "  expected bind starting with: $BIND_ARG"
      echo "  actual binds:"
      docker inspect -f '{{range .HostConfig.Binds}}    {{println .}}{{end}}' "$NAME" 2>&1
    } | diag
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "run with extra bind/port should succeed"
  { echo "DIAG test 1: run failed; codingbooth output:"; cat "$RUN_LOG"; } | diag
  FAILED=$((FAILED + 1))
fi
rm -f "$RUN_LOG"

# 2) Stop/start should preserve bind and extra port mapping.
STOP_LOG=$(mktemp); START_LOG=$(mktemp)
if run_coding_booth stop --name "$NAME" >"$STOP_LOG" 2>&1 \
  && run_coding_booth start --name "$NAME" --daemon >"$START_LOG" 2>&1; then

  if [[ "$(host_port "$NAME" 10000)" == "$UI_PORT" ]] \
    && [[ "$(host_port "$NAME" 12345)" == "$EXTRA_PORT" ]] \
    && has_bind "$NAME" "$BIND_ARG"; then
    print_test_result "true" "$0" "2" "stop/start preserves bind and port mappings"
  else
    print_test_result "false" "$0" "2" "expected bind and ports to persist after restart"
    {
      echo "DIAG test 2: stop/start succeeded but config drifted"
      echo "  UI_PORT=$UI_PORT, got $(host_port "$NAME" 10000)"
      echo "  EXTRA_PORT=$EXTRA_PORT, got $(host_port "$NAME" 12345)"
      echo "  binds after start:"
      docker inspect -f '{{range .HostConfig.Binds}}    {{println .}}{{end}}' "$NAME" 2>&1
    } | diag
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "stop/start should succeed"
  {
    echo "DIAG test 2: stop or start failed"
    echo "  stop output:"; cat "$STOP_LOG"
    echo "  start output:"; cat "$START_LOG"
    echo "  container state: $(docker inspect -f '{{.State.Status}}' "$NAME" 2>&1)"
  } | diag
  FAILED=$((FAILED + 1))
fi
rm -f "$STOP_LOG" "$START_LOG"

# 3) Bound content remains accessible after start.
#    On stop/start (keep-alive), the entrypoint does NOT re-run — Docker resumes
#    the process. Wait for the container to respond to exec.
READY=false
READY_AT=0
for i in $(seq 1 30); do
  if docker exec "$NAME" bash -lc 'true' >/dev/null 2>&1; then
    READY=true
    READY_AT=$i
    break
  fi
  sleep 1
done

if [[ "$READY" == true ]] && docker exec "$NAME" bash -lc 'test -f /tmp/lifecycle-extra/marker.txt' >/dev/null 2>&1; then
  print_test_result "true" "$0" "3" "bound directory remains mounted and readable"
else
  print_test_result "false" "$0" "3" "bound directory should remain mounted after start"
  {
    echo "DIAG test 3: READY=$READY (after ${READY_AT}s)"
    echo "  container state: $(docker inspect -f '{{.State.Status}}' "$NAME" 2>&1)"
    echo "  binds:"
    docker inspect -f '{{range .HostConfig.Binds}}    {{println .}}{{end}}' "$NAME" 2>&1
    echo "  HOST_DIR=$HOST_DIR (on host):"
    ls -la "$HOST_DIR" 2>&1 || echo "    (HOST_DIR missing)"
    if [[ "$READY" == true ]]; then
      echo "  /tmp/lifecycle-extra (in container):"
      docker exec "$NAME" bash -lc 'ls -la /tmp/lifecycle-extra/ 2>&1; echo "exit=$?"' 2>&1
      echo "  marker check:"
      docker exec "$NAME" bash -lc 'test -f /tmp/lifecycle-extra/marker.txt; echo "test exit=$?"' 2>&1
    else
      echo "  recent docker logs:"
      docker logs --tail 30 "$NAME" 2>&1
    fi
  } | diag
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
