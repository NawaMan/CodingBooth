#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a GUI command from `booth exec` reaches a desktop booth's X server.
#
#   1) exec --run on a desktop booth it creates runs an X client successfully,
#      with no wait loop in the command
#   2) an exec session has DISPLAY=:1 (no login shell, so it comes from the image)
#   3) exec --run on that booth after a stop (start path: booth-entry re-runs and
#      the X server comes up again from scratch) still reaches the display
#
# `xset q` is the X client: it exits non-zero when it cannot connect, and the
# desktop variants install it. Before #190 case 1 needed the caller to loop, and
# case 2 printed nothing. Case 3 is the race at its widest: `docker start`
# returns before the desktop session has started at all.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

NAME="exec-gui-$RANDOM"
PORT="$(pick_free_port)"
LOG="$0.log"
WORK="$(mktemp -d)"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

: > "$LOG"

# exec has no --variant to forward; config.toml carries it.
mkdir -p "$WORK/.booth"
printf 'variant = "desktop-xfce"\n' > "$WORK/.booth/config.toml"

booth_exec() {
  run_coding_booth exec --code "$WORK" --name "$NAME" --port "$PORT" --run --keep-alive "$@" 2>>"$LOG"
}

# --- 1: fresh create ---------------------------------------------------------
echo "=== exec --run (create) -- xset q ===" >> "$LOG"
STATUS=0
booth_exec -- xset q >> "$LOG" || STATUS=$?
if [[ "$STATUS" == "0" ]]; then
  print_test_result "true" "$0" "1" "exec --run on a new desktop booth reached its X server"
else
  print_test_result "false" "$0" "1" "exec --run -- xset q on a new desktop booth should exit 0, exited $STATUS"
  tail -30 "$LOG" >&2
  exit 1
fi

# --- 2: DISPLAY in an exec session -------------------------------------------
echo "=== exec -- printenv DISPLAY ===" >> "$LOG"
ACTUAL="$(booth_exec -- printenv DISPLAY || true)"
if [[ "$ACTUAL" == ":1" ]]; then
  print_test_result "true" "$0" "2" "An exec session on a desktop booth has DISPLAY=:1"
else
  print_test_result "false" "$0" "2" "An exec session on a desktop booth should have DISPLAY=:1, got '$ACTUAL'"
  tail -30 "$LOG" >&2
  exit 1
fi

# --- 3: after a stop, exec --run starts it and still waits -------------------
echo "=== docker stop; exec --run (start) -- xset q ===" >> "$LOG"
docker stop "$NAME" >/dev/null
STATUS=0
booth_exec -- xset q >> "$LOG" || STATUS=$?
if [[ "$STATUS" == "0" ]]; then
  print_test_result "true" "$0" "3" "exec --run on a stopped desktop booth started it and reached its X server"
else
  print_test_result "false" "$0" "3" "exec --run -- xset q after a stop should exit 0, exited $STATUS"
  tail -30 "$LOG" >&2
  exit 1
fi
