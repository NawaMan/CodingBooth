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
# wheel events itself. Mouse mode also captures left-drag as
# copy-pipe-and-cancel (highlight, then drop it on mouse-up); ttyd has no
# OSC 52, so that copy never reaches the host clipboard. The same config
# unbinds left-drag / double-click / triple-click, and the pane page injects
# cbForceTermSelect so xterm.js native-selects on a regular drag. This locks
# in the file, the live session, and the injected script.
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
CONF=$(docker exec "$NAME" cat /etc/tmux.conf 2>/dev/null || echo "")

if grep -qx 'set -g mouse on' <<<"$CONF"; then
  print_test_result "true" "$0" "1" "/etc/tmux.conf sets tmux's mouse mode on"
else
  print_test_result "false" "$0" "1" "/etc/tmux.conf should set tmux's mouse mode on"
  echo "  Actual: $CONF"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: left-drag is unbound so tmux does not copy-pipe-and-cancel a
# selection the browser can never copy (ttyd has no OSC 52).
# -------------------------------------------------------
if grep -qx 'unbind -T copy-mode MouseDragEnd1Pane' <<<"$CONF" \
   && grep -qx 'unbind -T copy-mode-vi MouseDragEnd1Pane' <<<"$CONF" \
   && grep -qx 'unbind -T root MouseDrag1Pane' <<<"$CONF"; then
  print_test_result "true" "$0" "2" "/etc/tmux.conf unbinds left-drag copy-mode"
else
  print_test_result "false" "$0" "2" "/etc/tmux.conf should unbind left-drag copy-mode"
  echo "  Actual: $CONF"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Tests 3–5: a real tmux session the 'coder' user starts (the same user and
# server start-ttyd-split's `tmux new-session -A -s s1..s4` uses) picks up
# the config live — not just present in an unread file. This is the real
# regression check: it's exactly what would silently stop being true if the
# config were ever dropped or shadowed by a later per-user ~/.tmux.conf.
#
# Not asserting on s1..s4 directly: ttyd only spawns its child (tmux
# new-session) on an actual websocket connection from a browser, which this
# test never makes, so those sessions would not exist yet.
# -------------------------------------------------------
docker exec -u coder "$NAME" tmux new-session -d -s mouse-check >/dev/null 2>&1

ACTUAL=$(docker exec -u coder "$NAME" tmux show-options -g mouse 2>/dev/null || echo "error")

if [[ "$ACTUAL" == "mouse on" ]]; then
  print_test_result "true" "$0" "3" "A tmux session the coder user starts picks up mouse mode from /etc/tmux.conf"
else
  print_test_result "false" "$0" "3" "A tmux session the coder user starts should pick up mouse mode from /etc/tmux.conf"
  echo "  Actual: $ACTUAL"
  FAILED=$((FAILED + 1))
fi

DRAG_END=$(docker exec -u coder "$NAME" tmux list-keys -T copy-mode 2>/dev/null | grep MouseDragEnd1Pane || true)
if [[ -z "$DRAG_END" ]]; then
  print_test_result "true" "$0" "4" "Live copy-mode has no MouseDragEnd1Pane (no copy-pipe-and-cancel)"
else
  print_test_result "false" "$0" "4" "Live copy-mode should not bind MouseDragEnd1Pane"
  echo "  Actual: $DRAG_END"
  FAILED=$((FAILED + 1))
fi

WHEEL=$(docker exec -u coder "$NAME" tmux list-keys -T root 2>/dev/null | grep WheelUpPane || true)
docker exec -u coder "$NAME" tmux kill-session -t mouse-check >/dev/null 2>&1

if [[ -n "$WHEEL" ]]; then
  print_test_result "true" "$0" "5" "Live root still binds WheelUpPane so the wheel scrolls tmux history"
else
  print_test_result "false" "$0" "5" "Live root should still bind WheelUpPane"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 6: a real browser's request (gzip'd) to a split-mode pane gets the
# script that forces xterm.js native selection on left-drag. Plain curl
# would miss a sub_filter that silently no-ops on a compressed body.
# -------------------------------------------------------
PANE_HTML=$(curl -s --compressed "http://127.0.0.1:${PORT}/s1/")

if [[ "$PANE_HTML" == *"cbForceTermSelect"* ]]; then
  print_test_result "true" "$0" "6" "split-mode pane /s1/ injects cbForceTermSelect even when gzip'd"
else
  print_test_result "false" "$0" "6" "split-mode pane /s1/ should inject cbForceTermSelect when gzip'd"
  echo "  First 300 chars of response: ${PANE_HTML:0:300}"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 7: the non-split fallback bakes the same script into ttyd's index
# (no nginx sits in front to sub_filter). The file is generated at image
# build, so a live booth is enough — no second container.
# -------------------------------------------------------
if docker exec "$NAME" grep -q cbForceTermSelect /usr/local/share/ttyd-nerd-font-index.html 2>/dev/null; then
  print_test_result "true" "$0" "7" "non-split ttyd index bakes in cbForceTermSelect"
else
  print_test_result "false" "$0" "7" "non-split ttyd index should bake in cbForceTermSelect"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
