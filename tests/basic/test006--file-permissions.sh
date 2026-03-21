#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: Verify UID/GID sync between host and container
# - Files created on host should be accessible inside container
# - Files created inside container should be owned by host user

set -euo pipefail

source ../common--source.sh

function generate_name() {
  local name
  while :; do
    name=$(printf "perm-test-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

function is_port_free() {
  local p="$1"

  # Prefer lsof (macOS + Linux); fall back to ss; fall back to nc
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
  local i

  for i in {1..100}; do
    port=$((40000 + RANDOM % 10001))  # Range 40000-50000 to avoid collision with other tests
    if is_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done

  echo "Failed to find free port in range 40000-50000 after 100 tries" >&2
  return 1
}

NAME="$(generate_name)"
PORT="$(random_free_port)"
HOST_FILE="host-created-file.txt"
CONTAINER_FILE="container-created-file.txt"
EXPECTED_UID=$(id -u)
EXPECTED_GID=$(id -g)

# Cleanup function
cleanup() {
  # Stop and remove container if it exists
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # Remove test files
  rm -f "$HOST_FILE" "$CONTAINER_FILE"
}
trap cleanup EXIT

# Clean up any leftover files from previous runs
cleanup

# Start container in daemon mode
echo "Starting container '$NAME' on port $PORT..."
run_coding_booth --variant base --name "$NAME" --port "$PORT" --daemon -- 'sleep 120'

# Wait for container to be ready (max ~30 seconds)
for i in {1..30}; do
  if docker inspect "$NAME" >/dev/null 2>&1; then
    # Check if container is running
    if docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q "true"; then
      break
    fi
  fi
  sleep 1
done

if ! docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "false" "$0" "0" "Container '$NAME' failed to start"
  exit 1
fi

# Give container a moment to fully initialize
sleep 2

# =============================================================================
# TEST 1: Create file on host, verify readable inside container
# =============================================================================
echo "Test content from host: $(date)" > "$HOST_FILE"

# Verify file exists and check ownership on host
if [[ ! -f "$HOST_FILE" ]]; then
  print_test_result "false" "$0" "1" "Failed to create file on host"
  exit 1
fi

# Read file from inside container (as coder user)
CONTAINER_READ=$(docker exec -u coder "$NAME" cat "/home/coder/code/$HOST_FILE" 2>&1) || {
  print_test_result "false" "$0" "1" "Container cannot read host-created file"
  echo "Error: $CONTAINER_READ"
  exit 1
}

HOST_CONTENT=$(cat "$HOST_FILE")
if [[ "$CONTAINER_READ" == "$HOST_CONTENT" ]]; then
  print_test_result "true" "$0" "1" "Container can read host-created file with correct content"
else
  print_test_result "false" "$0" "1" "Container read different content than host file"
  echo "Expected: $HOST_CONTENT"
  echo "Got: $CONTAINER_READ"
  exit 1
fi

# =============================================================================
# TEST 2: Create file inside container, verify ownership on host
# =============================================================================
CONTAINER_CONTENT="Test content from container: $(date)"
docker exec -u coder "$NAME" bash -c "echo '$CONTAINER_CONTENT' > /home/coder/code/$CONTAINER_FILE"

# Wait a moment for file to be written
sleep 1

# Check file exists on host
if [[ ! -f "$CONTAINER_FILE" ]]; then
  print_test_result "false" "$0" "2" "Container-created file not visible on host"
  exit 1
fi

# Verify content matches
HOST_READ=$(cat "$CONTAINER_FILE")
if [[ "$HOST_READ" == "$CONTAINER_CONTENT" ]]; then
  print_test_result "true" "$0" "2" "Host can read container-created file with correct content"
else
  print_test_result "false" "$0" "2" "Host read different content than container wrote"
  echo "Expected: $CONTAINER_CONTENT"
  echo "Got: $HOST_READ"
  exit 1
fi

# =============================================================================
# TEST 3: Verify container-created file has correct UID/GID on host
# =============================================================================
ACTUAL_UID=$(stat -c '%u' "$CONTAINER_FILE" 2>/dev/null || stat -f '%u' "$CONTAINER_FILE" 2>/dev/null)
ACTUAL_GID=$(stat -c '%g' "$CONTAINER_FILE" 2>/dev/null || stat -f '%g' "$CONTAINER_FILE" 2>/dev/null)

if [[ "$ACTUAL_UID" == "$EXPECTED_UID" ]]; then
  print_test_result "true" "$0" "3" "Container-created file has correct UID ($EXPECTED_UID)"
else
  print_test_result "false" "$0" "3" "Container-created file has wrong UID (expected $EXPECTED_UID, got $ACTUAL_UID)"
  exit 1
fi

if [[ "$ACTUAL_GID" == "$EXPECTED_GID" ]]; then
  print_test_result "true" "$0" "4" "Container-created file has correct GID ($EXPECTED_GID)"
else
  print_test_result "false" "$0" "4" "Container-created file has wrong GID (expected $EXPECTED_GID, got $ACTUAL_GID)"
  exit 1
fi

# =============================================================================
# TEST 4: Verify host user can modify container-created file
# =============================================================================
echo "Modified by host" >> "$CONTAINER_FILE"

MODIFIED_READ=$(docker exec -u coder "$NAME" cat "/home/coder/code/$CONTAINER_FILE" 2>&1) || {
  print_test_result "false" "$0" "5" "Container cannot read host-modified file"
  exit 1
}

if echo "$MODIFIED_READ" | grep -q "Modified by host"; then
  print_test_result "true" "$0" "5" "Host can modify container-created file, container sees changes"
else
  print_test_result "false" "$0" "5" "Container did not see host modifications"
  exit 1
fi

echo ""
echo "All file permission tests passed!"
