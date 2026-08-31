#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

function generate_name() {
  local name
  while :; do
    name=$(printf "exec-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

NAME="$(generate_name)"
PORT="$(pick_free_port)"

# Find the codingbooth binary path (for exec/shell which don't need --version)
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

# Helper: run codingbooth without --version injection (for exec/shell subcommands)
run_booth() {
  echo -e "${COLOR_BOOTH:-}> codingbooth $*${COLOR_RESET:-}" >&2
  "$BOOTH_BIN" "$@"
}

# Cleanup
cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
  rm -f "$0.envfile"
}
trap cleanup EXIT

# Start a keep-alive daemon container to exec into
run_coding_booth --variant base --name "$NAME" --port "$PORT" --daemon -- 'sleep 300' > "$0.log" 2>&1

# --- Wait for container to be fully ready (max ~30 seconds) ---
# Check both that the container is running AND that booth-entry has finished
# creating the coder user (otherwise exec runs as UID with "I have no name!").
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
if ! docker exec "$NAME" id coder >/dev/null 2>&1; then
  print_test_result "false" "$0" "0" "Container '$NAME' running but coder user not ready"
  exit 1
fi

# -------------------------------------------------------
# Test 1: Basic command execution
# -------------------------------------------------------
ACTUAL=$(run_booth exec "$NAME" -- echo hello-from-exec)
if [[ "$ACTUAL" == *"hello-from-exec"* ]]; then
  print_test_result "true" "$0" "1" "Basic exec command"
else
  print_test_result "false" "$0" "1" "Basic exec command (got: $ACTUAL)"
  exit 1
fi

# -------------------------------------------------------
# Test 2: Exit code forwarding (success)
# -------------------------------------------------------
if run_booth exec "$NAME" -- true; then
  print_test_result "true" "$0" "2" "Exit code forwarding (success)"
else
  print_test_result "false" "$0" "2" "Exit code forwarding (success)"
  exit 1
fi

# -------------------------------------------------------
# Test 3: Exit code forwarding (failure)
# -------------------------------------------------------
if run_booth exec "$NAME" -- false; then
  print_test_result "false" "$0" "3" "Exit code forwarding (failure) - expected non-zero"
  exit 1
else
  print_test_result "true" "$0" "3" "Exit code forwarding (failure)"
fi

# -------------------------------------------------------
# Test 4: -e flag sets environment variable
# -------------------------------------------------------
ACTUAL=$(run_booth exec "$NAME" -e TEST_VAR=booth_exec_test -- printenv TEST_VAR)
if [[ "$ACTUAL" == *"booth_exec_test"* ]]; then
  print_test_result "true" "$0" "4" "Environment variable via -e flag"
else
  print_test_result "false" "$0" "4" "Environment variable via -e flag (got: $ACTUAL)"
  exit 1
fi

# -------------------------------------------------------
# Test 5: --envfile flag loads variables from file
# -------------------------------------------------------
ENVFILE="$0.envfile"
echo "ENVFILE_VAR1=alpha" > "$ENVFILE"
echo "ENVFILE_VAR2=bravo" >> "$ENVFILE"

ACTUAL=$(run_booth exec "$NAME" --envfile "$ENVFILE" -- printenv ENVFILE_VAR1)
if [[ "$ACTUAL" == *"alpha"* ]]; then
  print_test_result "true" "$0" "5" "Environment variable via --envfile"
else
  print_test_result "false" "$0" "5" "Environment variable via --envfile (got: $ACTUAL)"
  exit 1
fi

# -------------------------------------------------------
# Test 6: --dir flag sets working directory
# -------------------------------------------------------
ACTUAL=$(run_booth exec "$NAME" --dir /tmp -- pwd)
if [[ "$ACTUAL" == *"/tmp"* ]]; then
  print_test_result "true" "$0" "6" "Working directory via --dir flag"
else
  print_test_result "false" "$0" "6" "Working directory via --dir flag (got: $ACTUAL)"
  exit 1
fi

# -------------------------------------------------------
# Test 7: --daemon detaches and returns immediately
# -------------------------------------------------------
DAEMON_FLAG=/tmp/booth-exec-daemon-flag
run_booth exec "$NAME" --daemon -- bash -c "sleep 2; echo detached-ok > $DAEMON_FLAG"

# Must have returned before the command finished.
if docker exec "$NAME" test -f "$DAEMON_FLAG"; then
  print_test_result "false" "$0" "7" "--daemon returned only after the command finished"
  exit 1
fi

for _ in $(seq 1 20); do
  docker exec "$NAME" test -f "$DAEMON_FLAG" && break
  sleep 1
done
ACTUAL=$(docker exec "$NAME" cat "$DAEMON_FLAG" 2>/dev/null || true)
if [[ "$ACTUAL" == *"detached-ok"* ]]; then
  print_test_result "true" "$0" "7" "Detached command via --daemon"
else
  print_test_result "false" "$0" "7" "Detached command via --daemon (got: $ACTUAL)"
  exit 1
fi

# -------------------------------------------------------
# Test 8: --daemon rejects incompatible combinations
# -------------------------------------------------------
if run_booth exec "$NAME" --daemon -it -- true 2>/dev/null; then
  print_test_result "false" "$0" "8" "--daemon -it should be rejected"
  exit 1
fi
if run_booth exec "$NAME" --daemon --run -- true 2>/dev/null; then
  print_test_result "false" "$0" "8" "--daemon --run without --keep-alive should be rejected"
  exit 1
fi
print_test_result "true" "$0" "8" "--daemon rejects -it and --run without --keep-alive"
