#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


# Manual Test: booth shell/exec --run [--keep-alive]
# Verifies that `--run` brings a booth up before connecting, and that the booth
# is returned to its prior state afterwards unless --keep-alive is given:
#   - run-from-scratch is removed afterwards (ephemeral)
#   - run-from-scratch with --keep-alive stays running
#   - an already-running booth is left untouched
#   - a stopped keep-alive booth is started, then returned to stopped
# Fully automated — no interactive input required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTH_BIN="${PROJECT_ROOT}/codingbooth"

# A scratch workspace whose basename is already a valid booth name (lowercase
# letters, digits, dashes only) so it matches the name `booth run` derives from
# the directory regardless of sanitization.
WORKDIR="${TMPDIR:-/tmp}/cb-run-test-$$-${RANDOM}"
mkdir -p "$WORKDIR"
NAME="$(basename "$WORKDIR")"

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "═══════════════════════════════════════════════════════════"
echo "  booth shell/exec --run — Manual Test"
echo "  workspace: $WORKDIR  (booth: $NAME)"
echo "═══════════════════════════════════════════════════════════"
echo ""

cd "$WORKDIR"

state_of() {
    local s
    s="$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)"
    [ -n "$s" ] && echo "$s" || echo missing
}

echo "Step 1: 'exec' WITHOUT --run on a non-existent booth should fail..."
if "$BOOTH_BIN" exec -- whoami >/dev/null 2>&1; then
    echo "  ERROR: exec succeeded with no booth and no --run"
    exit 1
fi
echo "  Correctly refused."

echo ""
echo "Step 2: 'exec --run' should create the booth (default 'base'), run, then REMOVE it..."
out="$("$BOOTH_BIN" exec --run -- whoami 2>/dev/null)"
state="$(state_of "$NAME")"
if [[ "$out" != "coder" ]]; then
    echo "  ERROR: unexpected output from exec --run: '$out' (expect coder)"
    exit 1
fi
if [[ "$state" != "missing" ]]; then
    echo "  ERROR: ephemeral booth should be removed afterwards, got state=$state"
    exit 1
fi
echo "  Ran as coder, booth removed afterwards (state=$state)."

echo ""
echo "Step 3: 'exec --run --keep-alive' should create the booth and LEAVE it running..."
out="$("$BOOTH_BIN" exec --run --keep-alive -- whoami 2>/dev/null)"
state="$(state_of "$NAME")"
ka="$(docker inspect -f '{{ index .Config.Labels "cb.keep-alive"}}' "$NAME" 2>/dev/null)"
if [[ "$out" != "coder" || "$state" != "running" || "$ka" != "true" ]]; then
    echo "  ERROR: keep-alive booth not running (out='$out', state=$state, keep-alive=$ka)"
    exit 1
fi
echo "  Ran as coder, booth still running and keep-alive (state=$state)."

echo ""
echo "Step 4: 'exec --run' on the already-running booth should NOT remove it..."
id_before="$(docker inspect -f '{{.Id}}' "$NAME")"
out="$("$BOOTH_BIN" exec --run -- whoami 2>/dev/null)"
state="$(state_of "$NAME")"
id_after="$(docker inspect -f '{{.Id}}' "$NAME" 2>/dev/null || echo gone)"
if [[ "$out" != "coder" || "$state" != "running" || "$id_before" != "$id_after" ]]; then
    echo "  ERROR: pre-existing booth was disturbed (state=$state, id $id_before -> $id_after)"
    exit 1
fi
echo "  Pre-existing booth left running and unchanged (state=$state)."

echo ""
echo "Step 5: a stopped keep-alive booth: 'exec --run' starts it, then returns it to STOPPED..."
"$BOOTH_BIN" stop "$NAME" >/dev/null 2>&1
state="$(state_of "$NAME")"
if [[ "$state" != "exited" ]]; then
    echo "  ERROR: expected the keep-alive booth to persist as exited, got state=$state"
    exit 1
fi
out="$("$BOOTH_BIN" exec "$NAME" --run -- whoami 2>/dev/null)"
state="$(state_of "$NAME")"
if [[ "$out" != "coder" || "$state" != "exited" ]]; then
    echo "  ERROR: exec --run should start then re-stop the keep-alive booth (out='$out', state=$state)"
    exit 1
fi
echo "  Started, ran as coder, returned to stopped (state=$state)."

echo ""
echo "Step 6: two concurrent --run sessions; the creator exits first but must NOT"
echo "        kill the booth while the second is still attached..."
docker rm -f "$NAME" >/dev/null 2>&1 || true
# Session A creates the booth and exits first (short command).
"$BOOTH_BIN" exec --run -- sleep 5 >/dev/null 2>&1 &
a_pid=$!
for _ in {1..60}; do [ "$(state_of "$NAME")" = "running" ] && break; sleep 1; done
if [[ "$(state_of "$NAME")" != "running" ]]; then
    echo "  ERROR: booth never came up for session A"
    exit 1
fi
# Session B attaches while A is still running and stays longer.
"$BOOTH_BIN" exec --run -- sleep 15 >/dev/null 2>&1 &
b_pid=$!

wait "$a_pid"
sleep 2
state="$(state_of "$NAME")"
if [[ "$state" != "running" ]]; then
    echo "  ERROR: creator's exit tore the booth down while B was attached (state=$state)"
    kill "$b_pid" 2>/dev/null || true
    exit 1
fi
echo "  Creator exited; booth still running for the second session (state=$state)."

wait "$b_pid"
sleep 2
state="$(state_of "$NAME")"
if [[ "$state" != "missing" ]]; then
    echo "  ERROR: booth should be removed once the last session left (state=$state)"
    exit 1
fi
echo "  Last session left; booth removed (state=$state)."

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Test PASSED"
echo "═══════════════════════════════════════════════════════════"
