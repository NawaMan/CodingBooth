#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: setup tty-owner gives the booth user its own terminal in `booth run`'s
# foreground shell.
#
# `docker run -it` allocates that pty while the container is still root, and
# booth-entry's `runuser` keeps it — so the coder shell sits on /dev/pts/0
# owned root:tty, mode 0620, and cannot open it by name. gpg's pinentry opens
# $GPG_TTY by name, so `pass show` and `gpg --quick-generate-key` fail.
#
# Case 1 locks in the bug itself (without the setup, the pty is root's), so this
# test notices if booth-entry ever starts handing the pty over on its own and
# the setup becomes dead weight. Cases 2-3: after the setup runs (as root, as a
# Boothfile `setup` line would), a new login shell owns and can read the pty.
#
# `script` gives the foreground booth a real terminal; without one docker run
# gets no -t and there is no pty to check.
# -----------------------------------------------------------------------------

set -uo pipefail

source ../common--source.sh

FAILED=0

NAME="tty-owner-$RANDOM"
PORT="$(pick_free_port)"
LOG="$0.log"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The in-booth probe: report the pty owner before the setup, run the built-in
# setup as root, then report again from a new login shell (which sources the
# profile script the setup installed).
PROBE='echo "BEFORE_OWNER=$(stat -c %U "$(tty)")"
sudo tty-owner--setup.sh >/dev/null
bash -lc '"'"'echo "AFTER_OWNER=$(stat -c %U "$(tty)")"; if [ -r "$(tty)" ]; then echo AFTER_READ=yes; else echo AFTER_READ=no; fi'"'"''

# Inner mode: run under `script`'s terminal, start the foreground booth.
if [[ "${1:-}" == "--inner" ]]; then
  # One string: booth run joins its command words into a `bash -lc` line, so
  # an inner `bash -c '...'` would lose its quoting.
  run_coding_booth --variant terminal --name "$2" --port "$3" -- "$PROBE"
  exit $?
fi

SHELL=/bin/bash timeout 300 script -qec "bash $(printf '%q' "$0") --inner $NAME $PORT" /dev/null \
  > "$LOG" 2>&1 < /dev/null

OUT="$(tr -d '\r' < "$LOG")"
BEFORE="$(sed -n 's/^.*BEFORE_OWNER=//p' <<<"$OUT" | tail -1)"
AFTER="$(sed -n 's/^.*AFTER_OWNER=//p'   <<<"$OUT" | tail -1)"
READ="$(sed -n 's/^.*AFTER_READ=//p'     <<<"$OUT" | tail -1)"

# -------------------------------------------------------
# Test 1: without the setup, the foreground shell's pty belongs to root.
# -------------------------------------------------------
if [[ "$BEFORE" == "root" ]]; then
  print_test_result "true"  "$0" "1" "booth run's foreground shell starts on a root-owned pty (the bug tty-owner fixes)"
else
  print_test_result "false" "$0" "1" "booth run's foreground shell should start on a root-owned pty, got owner '$BEFORE'"
  tail -20 "$LOG" >&2
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 2: after the setup, a login shell makes coder the pty's owner.
# -------------------------------------------------------
if [[ "$AFTER" == "coder" ]]; then
  print_test_result "true"  "$0" "2" "With tty-owner, a login shell chowns its pty to coder"
else
  print_test_result "false" "$0" "2" "With tty-owner, a login shell should chown its pty to coder, got owner '$AFTER'"
  FAILED=$((FAILED + 1))
fi

# -------------------------------------------------------
# Test 3: and coder can open it for reading — what pinentry needs.
# -------------------------------------------------------
if [[ "$READ" == "yes" ]]; then
  print_test_result "true"  "$0" "3" "With tty-owner, coder can read its own pty (gpg pinentry can open \$GPG_TTY)"
else
  print_test_result "false" "$0" "3" "With tty-owner, coder should be able to read its own pty, got '$READ'"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
