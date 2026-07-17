#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: shell/exec --run create flags (--port) and mismatch policy
#
# Covers:
# - exec --run --port creates a booth with the requested host UI port
# - matching --port against an existing booth connects
# - mismatched numeric --port refuses by default
# - --accept-existing connects despite mismatch (with a warning on stderr)
# - symbolic --port NEXT is not compared against an existing booth
# - ephemeral exec --run --port tears the booth down afterwards
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="connect-port-$RANDOM-$RANDOM"

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
  local s
  s="$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)" || s=""
  s="$(printf '%s' "$s" | tr -d '[:space:]')"
  if [[ -n "$s" ]]; then
    printf '%s\n' "$s"
  else
    printf '%s\n' "missing"
  fi
}

wait_coder_ready() {
  local name="$1"
  local i
  for i in {1..60}; do
    if docker inspect --format '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
      if docker exec "$name" id coder >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

PORT_A="$(random_free_port)"
PORT_B="$(random_free_port)"
while [[ "$PORT_B" == "$PORT_A" ]]; do
  PORT_B="$(random_free_port)"
done

# ---------------------------------------------------------------------------
# 1) exec --run --keep-alive --port creates a booth on that host port
# ---------------------------------------------------------------------------
# Tear down any leftover with the same name so --run takes the create path.
docker rm -f "$NAME" >/dev/null 2>&1 || true

set +e
CREATE_OUT="$(run_coding_booth exec --name "$NAME" --run --keep-alive --port "$PORT_A" -- whoami 2>&1)"
CREATE_EXIT=$?
set -e

if [[ $CREATE_EXIT -eq 0 ]] \
  && [[ "$CREATE_OUT" == *"coder"* ]] \
  && [[ "$(state_of "$NAME")" == "running" ]] \
  && [[ "$(host_port_10000 "$NAME")" == "$PORT_A" ]]; then
  print_test_result "true" "$0" "1" "exec --run --port creates booth on requested host port"
else
  print_test_result "false" "$0" "1" "exec --run --port should create on port $PORT_A"
  echo "  exit=$CREATE_EXIT state=$(state_of "$NAME") port=$(host_port_10000 "$NAME")"
  echo "  output: $CREATE_OUT"
  FAILED=$((FAILED + 1))
fi

# Ensure coder is ready for subsequent execs (create path already waited, but be safe).
if [[ "$(state_of "$NAME")" == "running" ]]; then
  wait_coder_ready "$NAME" || true
fi

# ---------------------------------------------------------------------------
# 2) matching --port against existing booth connects
# ---------------------------------------------------------------------------
set +e
MATCH_OUT="$(run_coding_booth exec --name "$NAME" --port "$PORT_A" -- whoami 2>&1)"
MATCH_EXIT=$?
set -e

if [[ $MATCH_EXIT -eq 0 ]] && [[ "$MATCH_OUT" == *"coder"* ]]; then
  print_test_result "true" "$0" "2" "matching --port connects to existing booth"
else
  print_test_result "false" "$0" "2" "matching --port should connect (exit=$MATCH_EXIT out=$MATCH_OUT)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 3) mismatched numeric --port refuses by default
# ---------------------------------------------------------------------------
set +e
MISMATCH_ERR="$(run_coding_booth exec --name "$NAME" --port "$PORT_B" -- whoami 2>&1)"
MISMATCH_EXIT=$?
set -e

if [[ $MISMATCH_EXIT -ne 0 ]] \
  && grep -q "does not match create flags" <<<"$MISMATCH_ERR" \
  && grep -q -- "--accept-existing" <<<"$MISMATCH_ERR"; then
  print_test_result "true" "$0" "3" "mismatched --port refuses without --accept-existing"
else
  print_test_result "false" "$0" "3" "mismatched --port should fail with accept-existing hint"
  echo "  exit=$MISMATCH_EXIT"
  echo "  output: $MISMATCH_ERR"
  FAILED=$((FAILED + 1))
fi

# Booth must still be running after the refused connect.
if [[ "$(state_of "$NAME")" == "running" ]]; then
  print_test_result "true" "$0" "4" "refused mismatch leaves existing booth running"
else
  print_test_result "false" "$0" "4" "booth should still be running after refused mismatch"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 5) --accept-existing connects despite mismatch (warn on stderr)
# ---------------------------------------------------------------------------
set +e
# Capture stderr separately so we can assert the warning; stdout is the command.
ACCEPT_STDOUT="$(run_coding_booth exec --name "$NAME" --port "$PORT_B" --accept-existing -- whoami 2>/tmp/cb-connect-accept-$$.err)"
ACCEPT_EXIT=$?
ACCEPT_STDERR="$(cat /tmp/cb-connect-accept-$$.err 2>/dev/null || true)"
rm -f /tmp/cb-connect-accept-$$.err
set -e

if [[ $ACCEPT_EXIT -eq 0 ]] \
  && [[ "$ACCEPT_STDOUT" == *"coder"* ]] \
  && grep -qi "warning" <<<"$ACCEPT_STDERR" \
  && grep -q "accept-existing" <<<"$ACCEPT_STDERR"; then
  print_test_result "true" "$0" "5" "--accept-existing connects with mismatch warning"
else
  print_test_result "false" "$0" "5" "--accept-existing should warn and connect"
  echo "  exit=$ACCEPT_EXIT stdout=$ACCEPT_STDOUT"
  echo "  stderr=$ACCEPT_STDERR"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 6) symbolic --port NEXT is not asserted against existing booth
# ---------------------------------------------------------------------------
set +e
NEXT_OUT="$(run_coding_booth exec --name "$NAME" --port NEXT -- whoami 2>&1)"
NEXT_EXIT=$?
set -e

if [[ $NEXT_EXIT -eq 0 ]] && [[ "$NEXT_OUT" == *"coder"* ]]; then
  print_test_result "true" "$0" "6" "--port NEXT against existing booth connects (not compared)"
else
  print_test_result "false" "$0" "6" "--port NEXT should connect without mismatch (exit=$NEXT_EXIT out=$NEXT_OUT)"
  FAILED=$((FAILED + 1))
fi

# ---------------------------------------------------------------------------
# 7) ephemeral exec --run --port: create, run, remove (no keep-alive)
# ---------------------------------------------------------------------------
docker rm -f "$NAME" >/dev/null 2>&1 || true

set +e
EPH_OUT="$(run_coding_booth exec --name "$NAME" --run --port "$PORT_B" -- whoami 2>&1)"
EPH_EXIT=$?
set -e
EPH_STATE="$(state_of "$NAME")"
# Prefer "does the container still exist?" over status string — stop may race
# inspect with a blank line on some Docker versions.
EPH_GONE=false
if ! docker inspect "$NAME" >/dev/null 2>&1; then
  EPH_GONE=true
fi

if [[ $EPH_EXIT -eq 0 ]] \
  && [[ "$EPH_OUT" == *"coder"* ]] \
  && [[ "$EPH_GONE" == true ]]; then
  print_test_result "true" "$0" "7" "ephemeral exec --run --port removes booth afterwards"
else
  print_test_result "false" "$0" "7" "ephemeral --run should run then remove (exit=$EPH_EXIT state=$EPH_STATE gone=$EPH_GONE)"
  echo "  output: $EPH_OUT"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
