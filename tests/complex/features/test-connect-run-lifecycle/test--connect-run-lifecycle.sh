#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: shell/exec --run returns the booth to the state it found it in
#
# Covers:
# 1. exec without --run, with no booth, is refused
# 2. exec --run creates the booth, runs, then removes it (ephemeral)
# 3. exec --run --keep-alive creates the booth and leaves it running
# 4. exec --run on an already-running booth leaves it untouched (same container)
# 5. a stopped keep-alive booth is started, then returned to stopped
# 6. two --run sessions: the creator leaving first must not tear the booth down
#    under the second
# 7. ...and the last one leaving removes it
#
# The booth is named after its folder (no --name on the create calls), so the
# folder name doubles as a check that the name is derived from it.
#
# Watch it: CB_TEST_WATCH=1 ./test--connect-run-lifecycle.sh
# pauses between steps and prints what to look at.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "$0")"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

# Resolved now: the booth runs from a scratch folder outside the checkout, and
# run_coding_booth looks for the binary relative to the current directory.
BOOTH_BIN="$(find_local_booth_build "$SCRIPT_DIR")"
booth() {
  trace_cmd '1;33' "> codingbooth $*"
  if [[ -n "${CB_DIAG_LOG:-}" ]]; then
    local rc=0
    printf '%s  === codingbooth %s\n' "$(date '+%H:%M:%S')" "$*" >>"$CB_DIAG_LOG"
    "$BOOTH_BIN" "$@" 2>>"$CB_DIAG_LOG" || rc=$?
    printf '%s  --- rc=%s\n' "$(date '+%H:%M:%S')" "$rc" >>"$CB_DIAG_LOG"
    return $rc
  fi
  "$BOOTH_BIN" "$@" 2>/dev/null
}

FAILED=0
# Outside the checkout on purpose: inside it, the booth would see a git
# worktree and mount it, which is not what this test is about. The basename is
# already a valid booth name (lowercase, digits, dashes).
WORKDIR="${TMPDIR:-/tmp}/cb-run-lifecycle-$$-$RANDOM"
NAME="$(basename "$WORKDIR")"
PORT="$(pick_free_port)"
mkdir -p "$WORKDIR"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

cd "$WORKDIR"

state_of() {
  local s
  s="$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)" || s=""
  s="$(printf '%s' "$s" | tr -d '[:space:]')"
  [[ -n "$s" ]] && printf '%s\n' "$s" || printf 'missing\n'
}

# wait_state <state> <seconds> — teardown happens after the command returns,
# so poll for it rather than reading the state once.
wait_state() {
  local want="$1" secs="$2" i
  for ((i = 0; i < secs * 2; i++)); do
    [[ "$(state_of "$NAME")" == "$want" ]] && return 0
    sleep 0.5
  done
  return 1
}

pass() { print_test_result "true" "$SELF" "$1" "$2"; }
fail() { print_test_result "false" "$SELF" "$1" "$2"; FAILED=$((FAILED + 1)); }

watch_pause "booth $NAME — folder $WORKDIR, port $PORT" \
  "in another terminal: watch -n1 'docker ps -a --filter name=$NAME'"

# ---------------------------------------------------------------------------
# 1) exec without --run, and no booth: refused
# ---------------------------------------------------------------------------
if booth exec -- whoami >/dev/null; then
  fail 1 "exec with no booth and no --run should be refused"
else
  pass 1 "exec with no booth and no --run is refused"
fi

# ---------------------------------------------------------------------------
# 2) exec --run: create, run, remove
# ---------------------------------------------------------------------------
OUT="$(booth exec --run --port "$PORT" -- whoami || true)"
if [[ "$OUT" == "coder" ]] && wait_state missing 30; then
  pass 2 "exec --run creates the booth, runs as coder, then removes it"
else
  fail 2 "exec --run should run then remove (out='$OUT' state=$(state_of "$NAME"))"
fi

# ---------------------------------------------------------------------------
# 3) exec --run --keep-alive: create, run, leave running
# ---------------------------------------------------------------------------
OUT="$(booth exec --run --keep-alive --port "$PORT" -- whoami || true)"
STATE="$(state_of "$NAME")"
KA="$(docker inspect -f '{{ index .Config.Labels "cb.keep-alive"}}' "$NAME" 2>/dev/null || true)"
if [[ "$OUT" == "coder" && "$STATE" == "running" && "$KA" == "true" ]]; then
  pass 3 "exec --run --keep-alive leaves the booth running, labelled keep-alive"
else
  fail 3 "keep-alive booth not left running (out='$OUT' state=$STATE keep-alive=$KA)"
fi

watch_pause "step 3 left $NAME running (keep-alive)" \
  "open http://localhost:$PORT  or  $BOOTH_BIN shell $NAME"

# ---------------------------------------------------------------------------
# 4) exec --run on a running booth: untouched
# ---------------------------------------------------------------------------
ID_BEFORE="$(docker inspect -f '{{.Id}}' "$NAME" 2>/dev/null || echo none)"
OUT="$(booth exec --run -- whoami || true)"
ID_AFTER="$(docker inspect -f '{{.Id}}' "$NAME" 2>/dev/null || echo gone)"
STATE="$(state_of "$NAME")"
if [[ "$OUT" == "coder" && "$STATE" == "running" && "$ID_BEFORE" == "$ID_AFTER" ]]; then
  pass 4 "exec --run on a running booth leaves it running and unchanged"
else
  fail 4 "running booth was disturbed (out='$OUT' state=$STATE id ${ID_BEFORE:0:12} -> ${ID_AFTER:0:12})"
fi

# ---------------------------------------------------------------------------
# 5) stopped keep-alive booth: started for the call, then stopped again
# ---------------------------------------------------------------------------
booth stop "$NAME" >/dev/null || true
if wait_state exited 30; then
  watch_pause "$NAME is stopped (keep-alive keeps the container)" \
    "next: exec --run should start it, run, and stop it again"
  OUT="$(booth exec "$NAME" --run -- whoami || true)"
  if [[ "$OUT" == "coder" ]] && wait_state exited 30; then
    pass 5 "exec --run starts a stopped keep-alive booth, then stops it again"
  else
    fail 5 "should start then re-stop the booth (out='$OUT' state=$(state_of "$NAME"))"
  fi
else
  fail 5 "keep-alive booth should persist as exited after stop (state=$(state_of "$NAME"))"
fi

# ---------------------------------------------------------------------------
# 6) two sessions; the creator leaves first
#
# Each session waits for a marker file in the mounted code folder instead of
# sleeping, so the test decides when each one leaves — and a watch pause in the
# middle cannot change the outcome.
# ---------------------------------------------------------------------------
docker rm -f "$NAME" >/dev/null 2>&1 || true
CODE=/home/coder/code
session() {  # <tag>: says it is attached, then waits to be released
  printf 'touch %s/.%s-attached; while [ ! -f %s/.%s-release ]; do sleep 0.5; done' \
    "$CODE" "$1" "$CODE" "$1"
}
wait_file() {
  local i
  for ((i = 0; i < 120; i++)); do [[ -f "$1" ]] && return 0; sleep 0.5; done
  return 1
}

booth exec --run --port "$PORT" -- bash -c "$(session a)" >/dev/null &
A_PID=$!
if ! wait_file "$WORKDIR/.a-attached"; then
  fail 6 "session A never came up (state=$(state_of "$NAME"))"
  kill "$A_PID" 2>/dev/null || true
else
  booth exec --run --port "$PORT" -- bash -c "$(session b)" >/dev/null &
  B_PID=$!
  if ! wait_file "$WORKDIR/.b-attached"; then
    fail 6 "session B never attached (state=$(state_of "$NAME"))"
    kill "$A_PID" "$B_PID" 2>/dev/null || true
  else
    watch_pause "two sessions attached to $NAME" \
      "next: the creator (A) leaves; the booth must stay up for B"
    touch "$WORKDIR/.a-release"
    wait "$A_PID" || true
    sleep 2
    STATE="$(state_of "$NAME")"
    if [[ "$STATE" == "running" ]]; then
      pass 6 "creator leaving first keeps the booth up for the other session"
    else
      fail 6 "creator's exit tore the booth down under session B (state=$STATE)"
    fi

    watch_pause "A has left; $NAME still serves B" \
      "next: B leaves; the booth should be removed"
    touch "$WORKDIR/.b-release"
    wait "$B_PID" || true
    if wait_state missing 30; then
      pass 7 "last session leaving removes the booth"
    else
      fail 7 "booth should be removed once the last session left (state=$(state_of "$NAME"))"
    fi
  fi
fi

exit $FAILED
