#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: tmux's own mouse mode is on, both baked into the image and live in the
# Console UI's actual session.
#
# Every pane in the Console UI (start-ttyd-split) runs its shell inside
# `tmux new-session -A`, and tmux keeps its whole display on the terminal's
# alternate screen. With tmux's own "mouse" option left at its default (off),
# tmux never asks the browser's terminal (xterm.js, via ttyd) for real mouse
# reporting — so xterm.js falls back to its built-in alt-screen behavior of
# translating wheel scroll into Up/Down key presses sent straight to whatever
# is running in the pane. At an idle prompt that's bash's readline: scrolling
# pages through command history instead of scrolling the overflowed output.
# The fix is a system-wide /etc/tmux.conf (`set -g mouse on`) so tmux claims
# wheel events itself. This locks in both halves: the config file ships in the
# image, and the session start-ttyd-split actually starts (s1) picks it up.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME="tmux-mouse-$RANDOM"
PORT="$(pick_free_port)"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_200() {
  local url="$1"
  for i in {1..40}; do
    if curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q 200; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_coding_booth --variant base --name "$NAME" --port "$PORT" --daemon > "$0.log" 2>&1

if ! wait_for_200 "http://127.0.0.1:${PORT}/__booth/health"; then
  print_test_result "false" "$0" "0" "Booth '$NAME' never answered /__booth/health"
  docker logs "$NAME" 2>&1 | tail -30 >&2
  exit 1
fi

# -------------------------------------------------------
# Test 1: the config ships system-wide in the image, so it applies no matter
# which user or session starts the tmux server.
# -------------------------------------------------------
ACTUAL=$(docker exec "$NAME" grep -c '^set -g mouse on$' /etc/tmux.conf 2>/dev/null || echo 0)

if [[ "$ACTUAL" == "1" ]]; then
  print_test_result "true" "$0" "1" "/etc/tmux.conf sets tmux's mouse mode on"
else
  print_test_result "false" "$0" "1" "/etc/tmux.conf should set tmux's mouse mode on"
  echo "  Actual: $(docker exec "$NAME" cat /etc/tmux.conf 2>&1)"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: a real tmux session the 'coder' user starts (the same user and
# server start-ttyd-split's `tmux new-session -A -s s1..s4` uses) picks up
# mouse mode live from /etc/tmux.conf — not just present in an unread config
# file. This is the real regression check: it's exactly what would silently
# stop being true if the config were ever dropped or shadowed by a later
# per-user ~/.tmux.conf.
#
# Not asserting on s1..s4 directly: ttyd only spawns its child (tmux
# new-session) on an actual websocket connection from a browser, which this
# test never makes, so those sessions would not exist yet.
# -------------------------------------------------------
docker exec -u coder "$NAME" tmux new-session -d -s mouse-check >/dev/null 2>&1

ACTUAL=$(docker exec -u coder "$NAME" tmux show-options -g mouse 2>/dev/null || echo "error")
docker exec -u coder "$NAME" tmux kill-session -t mouse-check >/dev/null 2>&1

if [[ "$ACTUAL" == "mouse on" ]]; then
  print_test_result "true" "$0" "2" "A tmux session the coder user starts picks up mouse mode from /etc/tmux.conf"
else
  print_test_result "false" "$0" "2" "A tmux session the coder user starts should pick up mouse mode from /etc/tmux.conf"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
