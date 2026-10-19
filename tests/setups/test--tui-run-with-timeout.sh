#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: run-with-timeout, the config-tui suite's wall-clock guard
#
# It wraps the one call that can wedge — `vhs` driving the real TUI through ttyd
# — and if it does not bite, a single wedged run hangs the whole suite forever
# *and* leaks the ttyd vhs started, because vhs never returns to its own
# reap-by-difference cleanup. A machine was found with 115 stray ttyd, the
# oldest 16 days, and that backlog is itself what tips later runs into wedging.
#
# The bug this locks out: the guard used `perl -e 'alarm ...; exec ...'`, and the
# only signal perl's alarm can raise is SIGALRM, which **Go ignores** — SIGALRM
# is _SigNotify with neither _SigKill nor _SigThrow, so with no signal.Notify
# listener the Go runtime handler just returns. vhs is a Go binary, so the
# deadline fired on time and nothing happened: 56 minutes under a 120-second
# limit. TERM alone is not enough either — the wedged vhs ignored SIGTERM and
# only died on SIGKILL.
#
# Nothing here runs vhs, ttyd or a container: a bash child that traps and
# ignores TERM stands in for "a process that will not take the polite signal",
# which is the property that actually broke the old guard. The suite's helper is
# sourced directly so the real function is under test, not a copy.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPERS="$REPO_ROOT/tests/config-tui/tui-helpers--source.sh"

if [ ! -f "$HELPERS" ]; then
    echo "❌ $HELPERS not found"
    exit 1
fi

# The helper file is a library for the config-tui suite and sets things up at
# source time; pull in just the function under test rather than running that.
WORK=$(mktemp -d)
# The stand-in below survives everything but SIGKILL by design, so clean it up
# explicitly: a broken guard leaves it running, and this test must not become
# the next thing that leaks a process.
# `return 0` is load-bearing: when an EXIT trap ends on a non-zero command its
# status replaces the script's own, and pkill exits non-zero when it matches
# nothing — which is the normal case here, since the guard already killed the
# stand-in. Without it a fully passing run reports failure to the suite runner.
cleanup() {
    pkill -9 -f "$WORK/stubborn.sh" 2>/dev/null || true
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT
FUNC="$WORK/run-with-timeout.sh"
awk '/^# Run a command under a wall-clock limit, portably\.$/{flag=1} flag; flag&&/^}$/{exit}' \
    "$HELPERS" > "$FUNC"

if ! grep -q 'function run-with-timeout()' "$FUNC"; then
    echo "❌ Could not extract run-with-timeout from $HELPERS"
    echo "   (the comment banner or the closing brace this test greps for may have changed)"
    exit 1
fi
# shellcheck disable=SC1090
source "$FUNC"

ALL_PASSED=true
TEST_NUM=0

pass_fail() {
    local ok="$1" desc="$2"
    TEST_NUM=$((TEST_NUM + 1))
    print_test_result "$ok" "$0" "$TEST_NUM" "$desc"
    [[ "$ok" == "true" ]] || ALL_PASSED=false
}

# A stand-in for the wedged vhs. It must ignore **ALRM as well as TERM**, and
# ALRM is the one that matters: the old guard raised SIGALRM and nothing else,
# and an ordinary bash child dies on SIGALRM, so a stub that merely ignored TERM
# would be killed by the broken guard and this whole test would pass against it.
# Go ignores SIGALRM — that is the property being stood in for — and the wedged
# vhs ignored SIGTERM too, so only SIGKILL ends this.
STUBBORN="$WORK/stubborn.sh"
cat > "$STUBBORN" <<'EOF'
#!/usr/bin/env bash
trap '' TERM INT ALRM
while :; do sleep 0.2; done
EOF
chmod +x "$STUBBORN"

# Bound the call under test with this test's own killer. A guard that does not
# bite makes run-with-timeout run forever, and a test that hangs is exactly as
# useless as the bug it is guarding: it has to *fail*, and say so. Deliberately
# not reusing run-with-timeout here — that is the thing on trial.
BOUNDED_HIT_CAP=false
bounded_run() {
    local cap="$1"; shift
    BOUNDED_HIT_CAP=false
    "$@" >/dev/null 2>&1 &
    local cmd=$!
    ( sleep "$cap"; kill -9 "$cmd" 2>/dev/null ) >/dev/null 2>&1 &
    local killer=$!
    wait "$cmd" 2>/dev/null
    local rc=$?
    if kill -0 "$killer" 2>/dev/null; then
        kill "$killer" 2>/dev/null          # finished on its own; stand the killer down
    else
        BOUNDED_HIT_CAP=true                # the killer already fired
    fi
    wait "$killer" 2>/dev/null
    return $rc
}

# ---- it returns, and quickly, against a process that ignores TERM and ALRM --
# The guard escalates TERM -> KILL with a 5s grace, so 2 + 5 plus slack; the cap
# is well past that, so hitting it means the guard never bit at all.
START=$(date +%s)
set +e
bounded_run 25 run-with-timeout 2 "$STUBBORN"
set -e
ELAPSED=$(( $(date +%s) - START ))

pass_fail "$([ "$BOUNDED_HIT_CAP" == "false" ] && echo true || echo false)" \
    "the guard bit on its own (did not have to be force-killed at the 25s cap)"
pass_fail "$([ "$ELAPSED" -lt 20 ] && echo true || echo false)" \
    "kills a process that ignores SIGTERM and SIGALRM (returned in ${ELAPSED}s, limit 20s)"
pass_fail "$([ "$ELAPSED" -ge 2 ] && echo true || echo false)" \
    "waits out the deadline rather than returning immediately (${ELAPSED}s >= 2s)"

# ---- the stubborn child is actually gone, not orphaned ----------------------
# A guard that returns while leaving the process alive is the leak that filled a
# machine with stray ttyd, so "it returned" is not on its own enough.
sleep 1
if pgrep -f "$STUBBORN" >/dev/null 2>&1; then
    LEAKED=true
else
    LEAKED=false
fi
pass_fail "$([ "$LEAKED" == "false" ] && echo true || echo false)" \
    "leaves no orphan behind after the deadline"

# ---- a command that finishes early is not killed, and is not delayed --------
START=$(date +%s)
set +e
OUT=$(run-with-timeout 30 bash -c 'echo done-early' 2>/dev/null)
RC=$?
set -e
ELAPSED=$(( $(date +%s) - START ))

pass_fail "$([ "$RC" -eq 0 ] && echo true || echo false)" \
    "a command that finishes early exits 0 (got $RC)"
pass_fail "$([ "$OUT" == "done-early" ] && echo true || echo false)" \
    "its stdout reaches the caller (got '$OUT')"
pass_fail "$([ "$ELAPSED" -lt 10 ] && echo true || echo false)" \
    "it is not held until the deadline (${ELAPSED}s)"

# ---- a non-zero exit is passed through, not swallowed -----------------------
set +e
run-with-timeout 30 bash -c 'exit 17' >/dev/null 2>&1
RC=$?
set -e
pass_fail "$([ "$RC" -eq 17 ] && echo true || echo false)" \
    "a command's own exit status survives the guard (got $RC)"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi

# Explicit: the bounded_run helper leaves the status of a reaped background job
# behind it, and the suite runner reads this script's exit code, not its output.
exit 0
