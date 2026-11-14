#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: a GUI command from `booth exec` reaches a Wayland desktop booth.
#
#   1) exec --run on a desktop-wayland booth it creates runs a Wayland client
#      (wlr-randr) successfully, with no wait loop in the command
#   2) the exec session has the compositor's WAYLAND_DISPLAY, and its socket is
#      in the session's XDG_RUNTIME_DIR
#   3) an X client (xset q) reaches Xwayland through the DISPLAY exec was given
#   4) a -e of the user's own wins over the desktop's value
#   5) exec --run on that booth after a stop (start-wayland runs again over the
#      last session's /tmp records) still reaches the compositor
#
# Unlike the X11 desktops, nothing here can be fixed in the image: the socket
# name depends on the compositor picked at run time, XDG_RUNTIME_DIR on coder's
# uid, and Xwayland's DISPLAY is known only to the compositor's children. So
# exec gets all three from `booth--desktop-ready wayland`. Before it, every one
# of these printed "no DISPLAY" or failed to connect. See test046 for X11.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

NAME="exec-wayland-$RANDOM"
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
printf 'variant = "desktop-wayland"\n' > "$WORK/.booth/config.toml"

booth_exec() {
  run_coding_booth exec --code "$WORK" --name "$NAME" --port "$PORT" --run --keep-alive "$@" 2>>"$LOG"
}

fail() {
  print_test_result "false" "$0" "$1" "$2"
  tail -30 "$LOG" >&2
  exit 1
}

# --- 1: fresh create, a Wayland client -----------------------------------------
echo "=== exec --run (create) -- wlr-randr ===" >> "$LOG"
STATUS=0
booth_exec -- wlr-randr >> "$LOG" || STATUS=$?
if [[ "$STATUS" == "0" ]]; then
  print_test_result "true" "$0" "1" "exec --run on a new Wayland booth reached its compositor"
else
  fail "1" "exec --run -- wlr-randr on a new Wayland booth should exit 0, exited $STATUS"
fi

# --- 2: the session env --------------------------------------------------------
echo "=== exec -- WAYLAND_DISPLAY socket ===" >> "$LOG"
ACTUAL="$(booth_exec -- bash -c 'test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" && echo "$WAYLAND_DISPLAY"' || true)"
if [[ "$ACTUAL" =~ ^wayland-[0-9]+$ ]]; then
  print_test_result "true" "$0" "2" "An exec session has WAYLAND_DISPLAY=$ACTUAL, a live socket in its XDG_RUNTIME_DIR"
else
  fail "2" "An exec session should have WAYLAND_DISPLAY naming a socket in XDG_RUNTIME_DIR, got '$ACTUAL'"
fi

# --- 3: an X client through Xwayland -------------------------------------------
echo "=== exec -- xset q (Xwayland) ===" >> "$LOG"
STATUS=0
booth_exec -- xset q >> "$LOG" || STATUS=$?
if [[ "$STATUS" == "0" ]]; then
  print_test_result "true" "$0" "3" "An X client from exec reached Xwayland"
else
  fail "3" "exec -- xset q should reach Xwayland and exit 0, exited $STATUS"
fi

# --- 4: the user's -e wins -----------------------------------------------------
echo "=== exec -e DISPLAY=:9 -- printenv DISPLAY ===" >> "$LOG"
ACTUAL="$(booth_exec -e DISPLAY=:9 -- printenv DISPLAY || true)"
if [[ "$ACTUAL" == ":9" ]]; then
  print_test_result "true" "$0" "4" "A -e DISPLAY of the user's own wins over the desktop's"
else
  fail "4" "-e DISPLAY=:9 should win over the desktop's DISPLAY, got '$ACTUAL'"
fi

# --- 5: after a stop, exec --run starts it and still waits ---------------------
echo "=== docker stop; exec --run (start) -- wlr-randr ===" >> "$LOG"
docker stop "$NAME" >/dev/null
STATUS=0
booth_exec -- wlr-randr >> "$LOG" || STATUS=$?
if [[ "$STATUS" == "0" ]]; then
  print_test_result "true" "$0" "5" "exec --run on a stopped Wayland booth started it and reached its compositor"
else
  fail "5" "exec --run -- wlr-randr after a stop should exit 0, exited $STATUS"
fi
