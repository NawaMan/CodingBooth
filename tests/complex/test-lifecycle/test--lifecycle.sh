#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: lifecycle round-trip
#
# This test runs a realistic lifecycle cycle for a keep-alive booth:
# 1) run --keep-alive with a short command
# 2) list --stopped includes the booth
# 3) start --daemon moves to running
# 4) restart keeps it running
# 5) stop keeps container (because keep-alive)
# 6) remove deletes it
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="lifecycle-$RANDOM-$RANDOM"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

container_state() {
  docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true
}

# 1) Create a keep-alive booth from a short command.
if run_coding_booth --variant base --name "$NAME" --keep-alive -- 'sleep 1' >/dev/null 2>&1; then
  if [[ "$(container_state "$NAME")" == "exited" ]]; then
    print_test_result "true" "$0" "1" "run --keep-alive created a stopped resumable booth"
  else
    print_test_result "false" "$0" "1" "expected booth to be in exited state after short command"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "run --keep-alive should succeed"
  FAILED=$((FAILED + 1))
fi

# 2) list --stopped should include the booth name.
if run_coding_booth list --stopped --name-only 2>/dev/null | grep -qx "$NAME"; then
  print_test_result "true" "$0" "2" "list --stopped includes the keep-alive booth"
else
  print_test_result "false" "$0" "2" "list --stopped should include booth name"
  FAILED=$((FAILED + 1))
fi

# 3) start --daemon should put booth in running state.
if run_coding_booth start --name "$NAME" --daemon >/dev/null 2>&1; then
  if [[ "$(container_state "$NAME")" == "running" ]]; then
    print_test_result "true" "$0" "3" "start --daemon resumes booth to running"
  else
    print_test_result "false" "$0" "3" "expected running state after start --daemon"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "3" "start --daemon should succeed"
  FAILED=$((FAILED + 1))
fi

# 4) restart should keep booth running.
if run_coding_booth restart --name "$NAME" >/dev/null 2>&1; then
  if [[ "$(container_state "$NAME")" == "running" ]]; then
    print_test_result "true" "$0" "4" "restart keeps booth running"
  else
    print_test_result "false" "$0" "4" "expected running state after restart"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "4" "restart should succeed"
  FAILED=$((FAILED + 1))
fi

# 5) stop should keep container because it was created with keep-alive.
if run_coding_booth stop --name "$NAME" >/dev/null 2>&1; then
  if [[ "$(container_state "$NAME")" == "exited" ]]; then
    print_test_result "true" "$0" "5" "stop keeps keep-alive booth as stopped container"
  else
    print_test_result "false" "$0" "5" "expected exited state after stop"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "5" "stop should succeed"
  FAILED=$((FAILED + 1))
fi

# 6) remove should delete booth container.
if run_coding_booth remove --name "$NAME" >/dev/null 2>&1; then
  if ! docker inspect "$NAME" >/dev/null 2>&1; then
    print_test_result "true" "$0" "6" "remove deletes booth container"
  else
    print_test_result "false" "$0" "6" "container should not exist after remove"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "6" "remove should succeed"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
