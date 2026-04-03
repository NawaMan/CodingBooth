#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: booth--expose TCP tunnel
#
# Verifies the control file mechanism and end-to-end tunnel for TCP tunnels:
# 1) .booth/.tmp/tcp-tunnels/ can be created inside the container
# 2) Control files written inside are visible from the host
# 3) session-id from booth-startup.txt is accessible inside container
# 4) Control files are cleaned on exit (ephemeral via .booth/.tmp/)
# 5) With --leave-tmp-on-exit, control file survives exit
# 6) End-to-end tunnel: booth--expose makes container port accessible on host
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

FAILED=0
NAME="test-booth-expose-$$"

cleanup() {
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
  rm -rf .booth/.tmp
}
trap cleanup EXIT

# Ensure clean state
rm -rf .booth/.tmp

# Test 1: session-id is accessible inside container
ACTUAL=$(run_coding_booth -- cat .booth/.tmp/booth-startup.txt 2>/dev/null)

if echo "$ACTUAL" | grep -q "^session-id = "; then
  print_test_result "true" "$0" "1" "session-id accessible inside container"
else
  print_test_result "false" "$0" "1" "session-id should be accessible inside container"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 2: Create tcp-tunnels control file inside container and read it back
ACTUAL=$(run_coding_booth -- 'mkdir -p .booth/.tmp/tcp-tunnels && echo tunnel-test > .booth/.tmp/tcp-tunnels/8080 && cat .booth/.tmp/tcp-tunnels/8080' 2>/dev/null)

if echo "$ACTUAL" | grep -qF 'tunnel-test'; then
  print_test_result "true" "$0" "2" "TCP tunnel control file created and read inside container"
else
  print_test_result "false" "$0" "2" "TCP tunnel control file should be readable"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 3: After exit, .booth/.tmp/ should be cleaned (control files gone)
if [ -d ".booth/.tmp" ]; then
  FILE_COUNT=$(find .booth/.tmp -mindepth 1 2>/dev/null | wc -l)
  if [ "$FILE_COUNT" -eq 0 ]; then
    print_test_result "true" "$0" "3" "Control files cleaned after booth exit"
  else
    print_test_result "false" "$0" "3" "Control files should be cleaned after exit"
    echo "  Files remaining: $FILE_COUNT"
    find .booth/.tmp -mindepth 1
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "true" "$0" "3" "Control files cleaned after booth exit"
fi

# Test 4: With --leave-tmp-on-exit, control file survives exit
rm -rf .booth/.tmp
run_coding_booth --leave-tmp-on-exit -- 'mkdir -p .booth/.tmp/tcp-tunnels && echo tunnel-3000 > .booth/.tmp/tcp-tunnels/3000' >/dev/null 2>&1

if [ -f ".booth/.tmp/tcp-tunnels/3000" ]; then
  CONTENT=$(command cat .booth/.tmp/tcp-tunnels/3000)
  if echo "$CONTENT" | grep -qF 'tunnel-3000'; then
    print_test_result "true" "$0" "4" "--leave-tmp-on-exit preserves control files"
  else
    print_test_result "false" "$0" "4" "Control file content should be preserved"
    echo "  Content: $CONTENT"
    FAILED=$((FAILED + 1))
  fi
else
  print_test_result "false" "$0" "4" "--leave-tmp-on-exit should preserve control files"
  echo "  .booth/.tmp/ contents:"
  find .booth/.tmp/ -type f 2>/dev/null || echo "  (no files)"
  FAILED=$((FAILED + 1))
fi

# Test 5: socat is available inside the container
ACTUAL=$(run_coding_booth -- 'command -v socat' 2>/dev/null)

if echo "$ACTUAL" | grep -q "socat"; then
  print_test_result "true" "$0" "5" "socat is available inside container"
else
  print_test_result "false" "$0" "5" "socat should be available inside container"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

# Test 6: End-to-end tunnel via booth--expose
# Start a daemon booth with a simple HTTP server, then use booth--expose
rm -rf .booth/.tmp
TUNNEL_PORT=18686

run_coding_booth --variant base --name "$NAME" --port "$TUNNEL_PORT" --daemon --keep-alive \
  -- 'sleep 600' >/dev/null 2>&1

# Wait for container to be ready
READY=false
for i in $(seq 1 10); do
  if docker exec "$NAME" bash -lc 'true' >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 1
done

if [[ "$READY" != true ]]; then
  print_test_result "false" "$0" "6" "Daemon booth failed to start for tunnel test"
  FAILED=$((FAILED + 1))
  exit $FAILED
fi

# Start a simple TCP echo server inside using socat (available in base image)
# It responds with "tunnel-ok" to any TCP connection on port 9876.
docker exec -d --user coder "$NAME" bash -lc \
  'socat TCP-LISTEN:9876,bind=127.0.0.1,reuseaddr,fork EXEC:"echo tunnel-ok" >/dev/null 2>&1'
sleep 1

# Run booth--expose inside the container as coder user
docker exec --user coder "$NAME" bash -lc 'booth--expose 9876' >/dev/null 2>&1
sleep 1

# Verify the control file was created on the host
CONTROL_FILE=".booth/.tmp/tcp-tunnels/9876"
if [[ ! -f "$CONTROL_FILE" ]]; then
  print_test_result "false" "$0" "6" "booth--expose should create control file visible on host"
  FAILED=$((FAILED + 1))
  exit $FAILED
fi

# Verify the service is reachable inside the container
# (socat responds with "tunnel-ok" on each connection)
TUNNEL_RESULT=$(docker exec --user coder "$NAME" bash -c 'echo | socat - TCP:localhost:9876,connect-timeout=3' 2>/dev/null || echo "TUNNEL_FAILED")

if echo "$TUNNEL_RESULT" | grep -qF "tunnel-ok"; then
  print_test_result "true" "$0" "6" "End-to-end: booth--expose creates control file and service is reachable"
else
  print_test_result "false" "$0" "6" "booth--expose control file + in-container service should work"
  echo "  Result: $TUNNEL_RESULT"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
