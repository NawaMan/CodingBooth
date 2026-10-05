#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the lifecycle log — .booth/.tmp/lifecycle.log on the host.
#
# A keep-alive base booth is started from a folder with a .booth/. Then:
#   1) the booth logs that it started
#   2) `booth logs --list` names the lifecycle log
#   3) a console pane's ttyd killed from the host is logged — the way a test
#      harness's stray cleanup once took every pane of a booth down unseen
#   4) booth--shutdown logs its reason, and the panes it takes down are not
#      reported as pane deaths
#   5) with the booth stopped, `booth logs --code <dir> lifecycle` still reads it
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

function generate_name() {
  local name
  while :; do
    name=$(printf "booth-lifecycle-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

BOOTH_BIN="$(find_local_booth_build)" || {
  echo "ERROR: Could not find codingbooth" >&2
  exit 1
}

run_booth() {
  echo -e "${COLOR_BOOTH:-}> codingbooth $*${COLOR_RESET:-}" >&2
  "$BOOTH_BIN" "$@"
}

NAME="$(generate_name)"
PORT="$(pick_free_port)"

WORK="$(mktemp -d)"
mkdir -p "$WORK/.booth"
LOG="$WORK/.booth/.tmp/lifecycle.log"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

run_coding_booth --variant base --code "$WORK" --name "$NAME" --port "$PORT" \
  --daemon --keep-alive --no-browser > "$0.log" 2>&1

# --- Wait for the four console panes ---
PANES=0
for i in {1..60}; do
  PANES=$(docker exec "$NAME" pgrep -c ttyd 2>/dev/null || true)
  if [[ "$PANES" == "4" ]]; then
    break
  fi
  sleep 1
done
if [[ "$PANES" != "4" ]]; then
  print_test_result "false" "$0" "0" "Booth '$NAME' should run 4 console panes, got '$PANES'"
  exit 1
fi

# -------------------------------------------------------
# Test 1: started
# -------------------------------------------------------
STARTED=$(grep -E " $NAME started .*mode=DAEMON port=$PORT" "$LOG" 2>/dev/null || true)
if [[ -n "$STARTED" ]]; then
  print_test_result "true" "$0" "1" "The booth logs its start"
else
  print_test_result "false" "$0" "1" "The booth should log its start (log: $(cat "$LOG" 2>/dev/null || echo missing))"
  exit 1
fi

# -------------------------------------------------------
# Test 2: --list names it
# -------------------------------------------------------
OUT=$(run_booth logs --name "$NAME" --list || true)
if echo "$OUT" | grep -qE "^lifecycle[[:space:]].*/\.booth/\.tmp/lifecycle\.log$"; then
  print_test_result "true" "$0" "2" "booth logs --list names the lifecycle log"
else
  print_test_result "false" "$0" "2" "booth logs --list should name the lifecycle log (output below)"
  echo "$OUT" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 3: a pane killed from outside is logged
# -------------------------------------------------------
# docker top prints host pids: the kill comes from the host, as the stray one did.
S2_PID=$(docker top "$NAME" -eo pid,args | awk '/ttyd .*-p 10002 /{print $1; exit}')
kill -TERM "$S2_PID"
PANE_LINE=""
for i in {1..20}; do
  PANE_LINE=$(grep -E " $NAME console-pane-exited pane=s2 port=10002 " "$LOG" 2>/dev/null || true)
  if [[ -n "$PANE_LINE" ]]; then
    break
  fi
  sleep 0.5
done
if [[ -n "$PANE_LINE" ]]; then
  print_test_result "true" "$0" "3" "A console pane's terminal killed from outside is logged"
else
  print_test_result "false" "$0" "3" "Killing pane s2's ttyd (host pid '$S2_PID') should be logged (log below)"
  cat "$LOG" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 4: booth--shutdown logs its reason, and not its pane kills
# -------------------------------------------------------
docker exec -u coder "$NAME" booth--shutdown --yes --reason=lifecycle-test >/dev/null 2>&1 || true
for i in {1..30}; do
  if [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)" != "true" ]]; then
    break
  fi
  sleep 1
done
SHUTDOWN=$(grep -cE " $NAME shutdown reason=lifecycle-test by=" "$LOG" 2>/dev/null || true)
PANE_DEATHS=$(grep -c " console-pane-exited " "$LOG" 2>/dev/null || true)
if [[ "$SHUTDOWN" == "1" && "$PANE_DEATHS" == "1" ]]; then
  print_test_result "true" "$0" "4" "booth--shutdown logs its reason; its own pane kills are not reported"
else
  print_test_result "false" "$0" "4" "Want 1 shutdown line and only the 1 earlier pane death, got $SHUTDOWN and $PANE_DEATHS (log below)"
  cat "$LOG" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 5: readable with the booth stopped
# -------------------------------------------------------
OUT=$(run_booth logs --code "$WORK" lifecycle || true)
if [[ "$OUT" == *" $NAME started "*" $NAME shutdown reason=lifecycle-test "* ]]; then
  print_test_result "true" "$0" "5" "booth logs --code <dir> lifecycle reads it with the booth stopped"
else
  print_test_result "false" "$0" "5" "booth logs --code <dir> lifecycle with the booth stopped (output below)"
  echo "$OUT" >&2
  exit 1
fi
