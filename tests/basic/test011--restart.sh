#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

WORKSPACE="$(mktemp -d)"
NAME="restart-test-$RANDOM"
LOG="$0.log"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORKSPACE"
  # Kill backgrounded booth process if still running
  [[ -n "${BOOTH_PID:-}" ]] && kill "$BOOTH_PID" 2>/dev/null || true
}
trap cleanup EXIT

# --- Set up workspace with .booth/ config and a startup.sh ---
mkdir -p "$WORKSPACE/.booth"
cat > "$WORKSPACE/.booth/config.toml" <<TOML
variant = "base"
name = "$NAME"
port = "RANDOM"
TOML

# startup.sh writes a timestamp so we can detect restarts
cat > "$WORKSPACE/.booth/startup.sh" <<'SH'
#!/bin/bash
date +%s%N > /tmp/.booth-start-stamp
SH
chmod +x "$WORKSPACE/.booth/startup.sh"

# .gitignore for .tmp/ (required by booth)
cat > "$WORKSPACE/.booth/.gitignore" <<'GI'
.env
.tmp/
GI

# Initialize git (booth needs a git repo for project name detection)
git -C "$WORKSPACE" init -q

# --- Run booth in command mode (foreground) in background ---
# The Go binary stays alive in command mode, so it can detect the restart marker.
# 'sleep 600' keeps the container running long enough for us to exec into it.
run_coding_booth \
  --code "$WORKSPACE" \
  -- 'sleep 600' \
  > "$LOG" 2>&1 &
BOOTH_PID=$!

# --- Wait for container to be ready ---
for i in {1..30}; do
  if docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
    if docker exec "$NAME" test -f /tmp/.booth-start-stamp 2>/dev/null; then
      break
    fi
  fi
  sleep 1
done

if ! docker exec "$NAME" test -f /tmp/.booth-start-stamp 2>/dev/null; then
  print_test_result "false" "$0" "0" "Container '$NAME' failed to start or startup.sh did not run"
  exit 1
fi

# -------------------------------------------------------
# Test 1: Capture initial session ID
# -------------------------------------------------------
SESSION_BEFORE=$(cat "$WORKSPACE/.booth/.tmp/booth-startup.txt" 2>/dev/null | grep session-id | awk '{print $3}')

if [[ -n "$SESSION_BEFORE" ]]; then
  print_test_result "true" "$0" "1" "Initial session ID captured: $SESSION_BEFORE"
else
  print_test_result "false" "$0" "1" "Could not read initial session ID from .booth/.tmp/booth-startup.txt"
  exit 1
fi

STAMP_BEFORE=$(docker exec "$NAME" cat /tmp/.booth-start-stamp 2>/dev/null)

if [[ -n "$STAMP_BEFORE" ]]; then
  print_test_result "true" "$0" "2" "Initial startup stamp captured: $STAMP_BEFORE"
else
  print_test_result "false" "$0" "2" "Could not read initial startup stamp"
  exit 1
fi

# -------------------------------------------------------
# Test 3: Trigger booth--restart from inside the container
# -------------------------------------------------------
docker exec "$NAME" bash -c 'booth--restart --yes' > "$LOG.restart" 2>&1 || true

# Wait for the container to come back up with a new stamp
for i in {1..60}; do
  if docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
    if docker exec "$NAME" test -f /tmp/.booth-start-stamp 2>/dev/null; then
      STAMP_AFTER=$(docker exec "$NAME" cat /tmp/.booth-start-stamp 2>/dev/null)
      if [[ -n "$STAMP_AFTER" && "$STAMP_AFTER" != "$STAMP_BEFORE" ]]; then
        break
      fi
    fi
  fi
  sleep 1
done

SESSION_AFTER=$(cat "$WORKSPACE/.booth/.tmp/booth-startup.txt" 2>/dev/null | grep session-id | awk '{print $3}')

if [[ -n "$SESSION_AFTER" && "$SESSION_AFTER" != "$SESSION_BEFORE" ]]; then
  print_test_result "true" "$0" "3" "Restart produced new session ID: $SESSION_BEFORE -> $SESSION_AFTER"
else
  print_test_result "false" "$0" "3" "Session ID did not change after restart (before=$SESSION_BEFORE after=$SESSION_AFTER)"
  exit 1
fi

# -------------------------------------------------------
# Test 4: startup.sh ran again after restart
# -------------------------------------------------------
STAMP_AFTER=$(docker exec "$NAME" cat /tmp/.booth-start-stamp 2>/dev/null)

if [[ -n "$STAMP_AFTER" && "$STAMP_AFTER" != "$STAMP_BEFORE" ]]; then
  print_test_result "true" "$0" "4" "startup.sh ran again after restart (stamp changed)"
else
  print_test_result "false" "$0" "4" "startup.sh did not re-run after restart (before=$STAMP_BEFORE after=$STAMP_AFTER)"
  exit 1
fi
