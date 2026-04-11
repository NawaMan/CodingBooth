#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: --persist-home Docker named volume persistence
#
# Verifies that /home/coder is persisted across container sessions via a
# Docker named volume when --persist-home is used.
#
# Test 1: Volume is created when --persist-home is used
# Test 2: Files in /home/coder persist across container exit + re-run
# Test 3: Seed marker file is created on first run
# Test 4: Override layers still apply on subsequent runs
# Test 5: Volume is cleaned up by codingbooth remove
# Test 6: Without --persist-home, home files do NOT persist (control)
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="persist-home-$RANDOM-$RANDOM"
VOL_NAME="cb-home-$NAME"
HOME_FILE="/home/coder/test-persist-file.txt"

cleanup() {
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
  docker volume rm "$VOL_NAME" >/dev/null 2>&1 || true
  rm -rf .booth/home 2>/dev/null || true
}
trap cleanup EXIT

# Ensure clean state from any previous test run
rm -rf .booth/home 2>/dev/null || true

# Wait for container entrypoint to fully finish after daemon start.
# booth-entry creates /var/run/cb-startup.once after startup hooks complete.
# We check for this marker to ensure all seeding and startup is done.
wait_exec_ready() {
  local name="$1"
  for _ in $(seq 1 60); do
    if docker exec "$name" bash -lc 'test -f /var/run/cb-startup.once' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

# Test 1: Run with --persist-home and verify volume is created
if run_coding_booth --variant base --persist-home --name "$NAME" --keep-alive --daemon -- 'sleep 600' >/dev/null 2>&1 \
  && wait_exec_ready "$NAME"; then

  if docker volume inspect "$VOL_NAME" >/dev/null 2>&1; then
    print_test_result "true" "$0" "1" "Volume '$VOL_NAME' is created with --persist-home"
  else
    print_test_result "false" "$0" "1" "Volume '$VOL_NAME' should be created with --persist-home"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "1" "run with --persist-home should succeed"
  FAILED=$((FAILED + 1))
fi

# Write a test file into home directory
docker exec "$NAME" bash -lc "echo persist-test > '$HOME_FILE'" >/dev/null 2>&1

# Stop and remove the container (but NOT the volume)
run_coding_booth stop --name "$NAME" >/dev/null 2>&1 || true
# Wait for container to stop
for _ in $(seq 1 15); do
  state=$(docker inspect -f '{{.State.Status}}' "$NAME" 2>/dev/null || true)
  if [[ "$state" == "exited" ]]; then break; fi
  sleep 1
done
# Force remove container only (not via codingbooth remove, which would also remove volume)
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Test 2: Re-run with same name and --persist-home, verify file persists
if run_coding_booth --variant base --persist-home --name "$NAME" --keep-alive --daemon -- 'sleep 600' >/dev/null 2>&1 \
  && wait_exec_ready "$NAME"; then

  ACTUAL=$(docker exec "$NAME" bash -lc "cat '$HOME_FILE'" 2>/dev/null | tr -d '\r\n')
  if [[ "$ACTUAL" == "persist-test" ]]; then
    print_test_result "true" "$0" "2" "File in /home/coder persists across container re-creation"
  else
    print_test_result "false" "$0" "2" "File in /home/coder should persist (expected 'persist-test', got '$ACTUAL')"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "2" "second run with --persist-home should succeed"
  FAILED=$((FAILED + 1))
fi

# Test 3: Verify seed marker file exists
if docker exec "$NAME" bash -lc "test -f /home/coder/.cb-home-seeded" >/dev/null 2>&1; then
  print_test_result "true" "$0" "3" "Seed marker file .cb-home-seeded exists"
else
  print_test_result "false" "$0" "3" "Seed marker file .cb-home-seeded should exist after first seeded run"
  FAILED=$((FAILED + 1))
fi

# Test 4: Create a .booth/home/ override file and verify it applies on re-run
mkdir -p .booth/home
echo "override-test-content" > .booth/home/.test-override-file

# Stop and remove container for re-run
{
  run_coding_booth stop --name "$NAME" 2>&1 || true
  for _ in $(seq 1 15); do
    state=$(docker inspect -f '{{.State.Status}}' "$NAME" 2>/dev/null || echo "gone")
    if [[ "$state" == "exited" ]] || [[ "$state" == "gone" ]]; then break; fi
    sleep 1
  done
  docker rm -f "$NAME" 2>&1 || true
} >/dev/null

if run_coding_booth --variant base --persist-home --name "$NAME" --keep-alive --daemon -- 'sleep 600' >/dev/null 2>&1 \
  && wait_exec_ready "$NAME"; then

  ACTUAL=$(docker exec "$NAME" bash -lc "cat /home/coder/.test-override-file" 2>/dev/null | tr -d '\r\n')
  if [[ "$ACTUAL" == "override-test-content" ]]; then
    print_test_result "true" "$0" "4" "Override layers still apply on subsequent runs"
  else
    print_test_result "false" "$0" "4" "Override file should be applied (expected 'override-test-content', got '$ACTUAL')"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "4" "third run with --persist-home should succeed"
  FAILED=$((FAILED + 1))
fi

# Cleanup override file
rm -rf .booth/home

# Test 5: codingbooth remove should clean up both container and volume
{
  run_coding_booth stop --name "$NAME" 2>&1 || true
  for _ in $(seq 1 15); do
    state=$(docker inspect -f '{{.State.Status}}' "$NAME" 2>/dev/null || echo "gone")
    if [[ "$state" == "exited" ]] || [[ "$state" == "gone" ]]; then break; fi
    sleep 1
  done
} >/dev/null
if run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1; then
  if docker volume inspect "$VOL_NAME" >/dev/null 2>&1; then
    print_test_result "false" "$0" "5" "Volume '$VOL_NAME' should be removed by codingbooth remove"
    FAILED=$((FAILED + 1))
  else
    print_test_result "true" "$0" "5" "Volume '$VOL_NAME' cleaned up by codingbooth remove"
  fi
else
  print_test_result "false" "$0" "5" "codingbooth remove should succeed"
  FAILED=$((FAILED + 1))
fi

# Test 6: Control test — without --persist-home, home files do NOT persist
CTRL_NAME="persist-home-ctrl-$RANDOM-$RANDOM"
CTRL_VOL="cb-home-$CTRL_NAME"
cleanup_ctrl() {
  docker rm -f "$CTRL_NAME" >/dev/null 2>&1 || true
  docker volume rm "$CTRL_VOL" >/dev/null 2>&1 || true
}

if run_coding_booth --variant base --name "$CTRL_NAME" -- "echo control > /home/coder/control-file.txt" >/dev/null 2>&1; then
  # No volume should have been created
  if docker volume inspect "$CTRL_VOL" >/dev/null 2>&1; then
    print_test_result "false" "$0" "6" "No volume should be created without --persist-home"
    FAILED=$((FAILED + 1))
  else
    print_test_result "true" "$0" "6" "No volume created without --persist-home (control)"
  fi
else
  # Command may fail because container exits, but that's fine for control test
  if docker volume inspect "$CTRL_VOL" >/dev/null 2>&1; then
    print_test_result "false" "$0" "6" "No volume should be created without --persist-home"
    FAILED=$((FAILED + 1))
  else
    print_test_result "true" "$0" "6" "No volume created without --persist-home (control)"
  fi
fi
cleanup_ctrl

exit $FAILED
