#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# timeout_run (common--source.sh) runs its command in a process group of its
# own, which is never the terminal's foreground group. Terminal access from such
# a group stops the whole group — SIGTTIN on a read, SIGTTOU on a tcsetattr —
# and the watchdog stops with it, so the deadline never fires and the call waits
# forever. Run from a shell, booth saw a terminal on stdin, started
# `docker run -i`, docker read the terminal, and complex/test-boothfile-bash sat
# for 2.5h on one `bash-3.2 --version`. CI has no terminal, so only a run from a
# shell ever saw it.
#
# timeout_run therefore ignores both signals in its command. This puts a real
# terminal on stdin with pty_run's `script` and asserts, inside it:
#   - a command that reads the terminal comes back at once instead of stopping;
#   - a stdin the caller piped in still reaches the command.
# A third case needs no terminal: a command that is stopped by other means still
# dies at its deadline, because the watchdog sends CONT behind the signal.
#
# It lives with the setups tests because they are the host-side suite that runs
# on timeout_run without a container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

# Inner mode: runs on script's terminal.
if [[ "${1:-}" == "--inner" ]]; then
    [[ -t 0 ]] && echo "inner-stdin=tty" || echo "inner-stdin=other"
    # `read` on the terminal from a background group: EIO, not a stop. The
    # -t guard is the proof of liveness — a stopped group never reaches it.
    timeout_run 10 bash -c '[ -t 0 ] && echo "cmd-stdin=tty" || echo "cmd-stdin=other"
                            read -r -t 3 line; echo "read-rc=$?"' || echo "timeout-rc=$?"
    echo hello | timeout_run 10 bash -c 'read -r line; echo "piped=$line"' || echo "timeout-rc=$?"
    exit 0
fi

FAILED=0
NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    NUM=$((NUM + 1))
    print_test_result "$ok" "$0" "$NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/          /'
        FAILED=$((FAILED + 1))
    fi
}

# ── A stopped command still dies at its deadline (no terminal needed) ────────
#
# The command stops itself and holds a TERM handler. A stopped process does not
# act on a catchable signal until it is continued, so without the CONT the TERM
# sits pending, the trap never runs, and the grace kill ends it instead (137).
START=$(date +%s)
STOPPED=$(timeout_run 3 bash -c 'trap "echo trap-ran; exit 0" TERM
                                 kill -STOP $$
                                 sleep 60' 2>&1) || STOPPED_RC=$?
ELAPSED=$(( $(date +%s) - START ))

if grep -q "trap-ran" <<< "$STOPPED" && [[ "$ELAPSED" -lt 20 ]]; then
    check "true"  "A stopped command takes the deadline's signal once it is continued"
else
    check "false" "A stopped command takes the deadline's signal once it is continued" \
        "elapsed=${ELAPSED}s rc=${STOPPED_RC:-0} out=$STOPPED"
fi

# ── Terminal access does not stop the command ───────────────────────────────
#
# `script` is util-linux, which Git Bash does not ship.
if ! command -v script >/dev/null 2>&1; then
    echo "SKIP: no 'script' to put a terminal on stdin"
    [[ "$FAILED" -eq 0 ]] || exit 1
    exit 0
fi

START=$(date +%s)
OUT=$(SHELL=/bin/bash pty_run -t 40 /dev/null "$SCRIPT_DIR/$(basename "$0")" --inner 2>&1 | tr -d '\r') || true
ELAPSED=$(( $(date +%s) - START ))

# Without a terminal on the inner stdin, the cases below prove nothing. A host
# that has `script` but will not hand out a pty (a sandbox, a container with no
# /dev/ptmx) is the same case as a host with no `script` at all, so it skips —
# a case that cannot run must not read as a case that failed.
if ! grep -q "inner-stdin=tty" <<< "$OUT"; then
    if grep -qE "openpty|ptmx|Operation not permitted" <<< "$OUT"; then
        echo "SKIP: this host has 'script' but no pty to give it: $OUT"
        [[ "$FAILED" -eq 0 ]] || exit 1
        exit 0
    fi
    check "false" "script put a terminal on the inner stdin" "out=$OUT"
    exit 1
fi

if grep -q "read-rc=" <<< "$OUT" && ! grep -q "timeout-rc=" <<< "$OUT" && [[ "$ELAPSED" -lt 30 ]]; then
    check "true"  "A command under timeout_run reading the terminal is not stopped"
else
    check "false" "A command under timeout_run reading the terminal is not stopped" \
        "elapsed=${ELAPSED}s out=$OUT"
fi

if grep -q "piped=hello" <<< "$OUT"; then
    check "true"  "A stdin piped into timeout_run still reaches the command"
else
    check "false" "A stdin piped into timeout_run still reaches the command" "out=$OUT"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
