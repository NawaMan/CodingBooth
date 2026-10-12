#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# timeout_run (common--source.sh) must not hand its command the terminal as
# stdin. The command runs in a process group of its own, so a read of the
# terminal stops the whole group with SIGTTIN, the watchdog included, and the
# call waits forever: run from a shell, booth's `docker run -i` did exactly that
# and parked complex/test-boothfile-bash for 2.5h. CI has no terminal, so only a
# run from a shell ever saw it. This puts a real terminal on stdin with
# pty_run's `script`, then, inside it:
#   - a command that reads stdin gets EOF at once instead of being stopped;
#   - a stdin the caller piped in still reaches the command.
# It lives with the setups tests because they are the host-side suite that runs
# on timeout_run without a container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

# Inner mode: runs on script's terminal.
if [[ "${1:-}" == "--inner" ]]; then
    [[ -t 0 ]] && echo "inner-stdin=tty" || echo "inner-stdin=other"
    timeout_run 10 bash -c '[ -t 0 ] && echo "cmd-stdin=tty" || echo "cmd-stdin=other"
                           read -r -t 3 line; echo "read-rc=$?"' || echo "timeout-rc=$?"
    echo hello | timeout_run 10 bash -c 'read -r line; echo "piped=$line"' || echo "timeout-rc=$?"
    exit 0
fi

# `script` is util-linux, which Git Bash does not ship.
if ! command -v script >/dev/null 2>&1; then
    echo "SKIP: no 'script' to put a terminal on stdin"
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

START=$(date +%s)
OUT=$(SHELL=/bin/bash pty_run -t 40 /dev/null "$SCRIPT_DIR/$(basename "$0")" --inner 2>&1 | tr -d '\r') || true
ELAPSED=$(( $(date +%s) - START ))

# Without a terminal on the inner stdin, the cases below prove nothing.
if ! grep -q "inner-stdin=tty" <<< "$OUT"; then
    check "false" "script put a terminal on the inner stdin" "out=$OUT"
    exit 1
fi

if grep -q "cmd-stdin=other" <<< "$OUT" && grep -q "read-rc=1" <<< "$OUT" && [[ "$ELAPSED" -lt 20 ]]; then
    check "true"  "A command under timeout_run reads EOF, not the terminal, and is not stopped"
else
    check "false" "A command under timeout_run reads EOF, not the terminal, and is not stopped" "elapsed=${ELAPSED}s out=$OUT"
fi

if grep -q "piped=hello" <<< "$OUT" && ! grep -q "timeout-rc=" <<< "$OUT"; then
    check "true"  "A stdin piped into timeout_run still reaches the command"
else
    check "false" "A stdin piped into timeout_run still reaches the command" "out=$OUT"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
