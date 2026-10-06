#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: booth-entry gives the booth user the foreground pty of `booth run`.
#
# `docker run -t` allocates that pty while the container is still root.
# booth-entry chowns the /dev/pts slave to coder before any user process, and
# leaves the mode at 0620, so gpg pinentry can open $GPG_TTY. A start with no
# terminal has nothing to chown and must still boot.
#
# The script under test is bind-mounted over the image's /usr/local/bin/booth-entry,
# so this checks the tree rather than whichever entry the image was built with.
#
# `script` gives the foreground booth a real terminal; without one docker run
# gets no -t and there is no pty to check.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME="entry-pty-$RANDOM"
PORT="$(pick_free_port)"
NAME2="entry-pty-notty-$RANDOM"
PORT2="$(pick_free_port_other_than "$PORT")"
LOG="$0.log"
LOG2="$0.notty.log"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ENTRY="$REPO/variants/base/booth-entry"
WORK="$(mktemp -d)"

cleanup() {
  docker rm -f "$NAME" "$NAME2" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/.booth"
printf 'variant = "base"\nrun-args = ["-v", "%s:/usr/local/bin/booth-entry:ro"]\n' \
  "$ENTRY" > "$WORK/.booth/config.toml"

PROBE='echo "OWNER=$(stat -c %U "$(tty)")"; echo "MODE=$(stat -c %a "$(tty)")"; if [ -r "$(tty)" ]; then echo READ=yes; else echo READ=no; fi'

# Inner mode: run under `script`'s terminal, start the foreground booth.
if [[ "${1:-}" == "--inner" ]]; then
  run_coding_booth --code "$2" --variant base --hide-welcome --name "$3" --port "$4" -- "$PROBE"
  exit $?
fi

SHELL=/bin/bash timeout 300 script -qec "bash $(printf '%q' "$0") --inner $(printf '%q' "$WORK") $NAME $PORT" /dev/null \
  > "$LOG" 2>&1 < /dev/null

OUT="$(tr -d '\r' < "$LOG")"
OWNER="$(sed -n 's/^.*OWNER=//p' <<<"$OUT" | tail -1)"
MODE="$(sed -n 's/^.*MODE=//p'   <<<"$OUT" | tail -1)"
READ="$(sed -n 's/^.*READ=//p'   <<<"$OUT" | tail -1)"

# -------------------------------------------------------
# Test 1: the foreground shell's pty belongs to coder.
# -------------------------------------------------------
if [[ "$OWNER" == "coder" ]]; then
  print_test_result "true"  "$0" "1" "booth run's foreground shell starts on a pty owned by coder"
else
  print_test_result "false" "$0" "1" "booth run's foreground shell should start on a pty owned by coder, got owner '$OWNER'"
  tail -30 "$LOG" >&2
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: the mode stays 0620. Group tty can still write; owner can read.
# -------------------------------------------------------
if [[ "$MODE" == "620" ]]; then
  print_test_result "true"  "$0" "2" "The foreground pty stays mode 0620"
else
  print_test_result "false" "$0" "2" "The foreground pty should stay mode 0620, got '$MODE'"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: coder can open it for reading — what pinentry needs.
# -------------------------------------------------------
if [[ "$READ" == "yes" ]]; then
  print_test_result "true"  "$0" "3" "coder can read its foreground pty (gpg pinentry can open \$GPG_TTY)"
else
  print_test_result "false" "$0" "3" "coder should be able to read its foreground pty, got '$READ'"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 4: a start with no terminal still runs the command.
# -------------------------------------------------------
NOTTY_RC=0
run_coding_booth --code "$WORK" --variant base --hide-welcome --name "$NAME2" --port "$PORT2" -- 'echo NO_TTY_OK' \
  < /dev/null > "$LOG2" 2>&1 || NOTTY_RC=$?
NOTTY_OUT="$(tr -d '\r' < "$LOG2")"
if [[ "$NOTTY_RC" -eq 0 && "$NOTTY_OUT" == *"NO_TTY_OK"* ]]; then
  print_test_result "true"  "$0" "4" "A booth run with no terminal still runs its command"
else
  print_test_result "false" "$0" "4" "A booth run with no terminal should run its command, got rc=$NOTTY_RC"
  tail -30 "$LOG2" >&2
  FAILED=$((FAILED + 1))
fi

exit $FAILED
