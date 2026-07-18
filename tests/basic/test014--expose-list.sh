#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: listing a booth's ports from both sides.
#
# A base booth is started from a real project dir (so .booth/.tmp/ports.json is
# written) with the front door plus one extra published port. Then:
#   1) `booth expose list` (host) reports the front door mapped to the booth port
#   2) `booth expose list` (host) reports the extra published port
#   3) `booth--expose list` (in-booth) reads the same manifest and reports both
#
# The manifest is the shared contract: the host command reads it and confirms
# against `docker port`; the in-booth command reads it and adds live `ss` data.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

CONTAINER_PORT=9999

function generate_name() {
  local name
  while :; do
    name=$(printf "expose-list-%04d" $((RANDOM % 10000)))
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

function random_free_port() {
  local port
  for i in {1..100}; do
    port=$((50000 + RANDOM % 10001))
    if is_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done
  echo "Failed to find free port in range 50000-60000 after 100 tries" >&2
  return 1
}

# Find the codingbooth binary for the exec/expose subcommands (no --version).
BOOTH_BIN=""
check_dir="$(pwd)"
for _ in 1 2 3 4 5; do
  if [[ -x "$check_dir/codingbooth" ]]; then
    BOOTH_BIN="$check_dir/codingbooth"
    break
  fi
  check_dir="$(dirname "$check_dir")"
done
if [[ -z "$BOOTH_BIN" ]]; then
  echo "ERROR: Could not find codingbooth" >&2
  exit 1
fi

run_booth() {
  echo -e "${COLOR_BOOTH:-}> codingbooth $*${COLOR_RESET:-}" >&2
  "$BOOTH_BIN" "$@"
}

NAME="$(generate_name)"
PORT="$(random_free_port)"
EXTRA="$(random_free_port)"
while [[ "$EXTRA" == "$PORT" ]]; do EXTRA="$(random_free_port)"; done

# A real project dir so the run pipeline writes .booth/.tmp/ports.json (the
# manifest both list commands read).
WORK="$(mktemp -d)"
mkdir -p "$WORK/.booth"
printf 'variant = "base"\nport = "%s"\nrun-args = ["--publish", "%s:%s"]\n' \
  "$PORT" "$EXTRA" "$CONTAINER_PORT" > "$WORK/.booth/config.toml"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Start a daemon booth from the project dir. A base booth in daemon mode stays
# alive on its own web stack (so the front door genuinely listens); no command.
run_coding_booth --code "$WORK" --name "$NAME" --daemon > "$0.log" 2>&1

# --- Wait for the container to be running and the coder user to be ready ---
for i in {1..30}; do
  if docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
    if docker exec "$NAME" id coder >/dev/null 2>&1; then
      break
    fi
  fi
  sleep 1
done

if ! docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
  print_test_result "false" "$0" "0" "Container '$NAME' failed to start"
  exit 1
fi

# -------------------------------------------------------
# Test 1: host `expose list` reports the front door on the booth port
# -------------------------------------------------------
HOST_OUT=$(run_booth expose list --name "$NAME")
FRONT_LINE=$(echo "$HOST_OUT" | grep -E '^10000[[:space:]]' || true)
if [[ "$FRONT_LINE" == *"127.0.0.1:$PORT"* && "$FRONT_LINE" == *"front door"* ]]; then
  print_test_result "true" "$0" "1" "Host expose list shows the front door on booth port $PORT"
else
  print_test_result "false" "$0" "1" "Host expose list front door (got: ${FRONT_LINE:-<none>})"
  echo "$HOST_OUT" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 2: host `expose list` reports the extra published port, confirmed live
# -------------------------------------------------------
PUB_LINE=$(echo "$HOST_OUT" | grep -E "^${CONTAINER_PORT}[[:space:]]" || true)
if [[ "$PUB_LINE" == *":$EXTRA"* && "$PUB_LINE" == *"published"* && "$PUB_LINE" == *"yes"* ]]; then
  print_test_result "true" "$0" "2" "Host expose list shows published $CONTAINER_PORT on host $EXTRA (live)"
else
  print_test_result "false" "$0" "2" "Host expose list published port (got: ${PUB_LINE:-<none>})"
  echo "$HOST_OUT" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 3: in-booth `booth--expose list` reads the same manifest
# -------------------------------------------------------
BOOTH_OUT=$(run_booth exec "$NAME" -- booth--expose list)
if echo "$BOOTH_OUT" | grep -qE '^10000[[:space:]]' && \
   echo "$BOOTH_OUT" | grep -qE "^${CONTAINER_PORT}[[:space:]]" && \
   [[ "$BOOTH_OUT" == *"front door"* ]]; then
  print_test_result "true" "$0" "3" "In-booth booth--expose list shows front door and published $CONTAINER_PORT"
else
  print_test_result "false" "$0" "3" "In-booth booth--expose list (output below)"
  echo "$BOOTH_OUT" >&2
  exit 1
fi
