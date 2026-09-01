#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: cb-android-emulator's CPU-translation guard
#
# android-emulator--setup.sh generates a launcher (cb-android-emulator) that
# refuses to start when this container's own architecture is being
# transparently re-executed through Docker Desktop's amd64-on-Apple-Silicon
# translation — confirmed (by hand, on real hardware) to crash the real
# emulator three different ways under that condition, rather than just run
# slowly. Nothing here exercises that crash directly: it asserts the launcher
# recognizes the condition and reacts correctly, which is what a future edit
# to the setup script could silently break.
#
# The launcher is generated as a heredoc inside the setup script rather than
# shipped as its own file, so it is extracted here the same way it was
# hand-verified during development: everything between the
# `cat >"$LAUNCHER" <<'LAUNCHEOF'` / `LAUNCHEOF` markers. Running the extracted
# copy directly, with CB_ROSETTA_MARKER pointed at a throwaway file instead of
# the real /sys/module/rosetta, makes both the "translated" and "native"
# states reproducible on any host — no Docker, no root, no Apple Silicon
# required.
#
# There is no real Android SDK on the test host, so every run here fails past
# the guard on the launcher's own "no system image installed" check — that is
# expected and irrelevant to what is under test. It is deliberately NOT
# asserted on: whether that later check fails via its own friendly message or
# via a pipefail-triggered ERR trap depends on shell/host specifics unrelated
# to this guard, so the assertions below stick to what the guard itself is
# responsible for — the CPU-translation message, the force override, and the
# device-connect.sh mention.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/android-emulator--setup.sh"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

LAUNCHER="$WORK/cb-android-emulator"
awk '/^cat >"\$LAUNCHER" <<.LAUNCHEOF./{flag=1;next}/^LAUNCHEOF$/{flag=0}flag' \
    "$SETUP_SCRIPT" > "$LAUNCHER"
chmod +x "$LAUNCHER"

if [ ! -s "$LAUNCHER" ]; then
    echo "❌ Could not extract the LAUNCHEOF heredoc from $SETUP_SCRIPT"
    echo "   (the cat/here-doc markers this test greps for may have changed)"
    exit 1
fi

ALL_PASSED=true
TEST_NUM=0

# Runs the extracted launcher with a controlled marker, an empty stdin (so
# pause_on_error's `read` never blocks the test), and an isolated $HOME/$PWD
# so device-connect.sh detection is under this test's control, not the host's.
# Sets RUN_OUT and RUN_EXIT rather than returning them, since a failing exit
# status (the common case here) must not trip this script's own `set -e`.
RUN_OUT=""
RUN_EXIT=0
run_launcher() {
    local marker="$1" home="$2" pwd_dir="$3"; shift 3
    RUN_OUT=$(cd "$pwd_dir" \
        && CB_ROSETTA_MARKER="$marker" HOME="$home" "$@" bash "$LAUNCHER" 2>&1 </dev/null) \
        && RUN_EXIT=0 || RUN_EXIT=$?
}

BLOCKED_MSG="The Android emulator cannot run here"
FORCE_MSG="attempting to launch anyway"

PRESENT="$WORK/rosetta-present"
touch "$PRESENT"
ABSENT="$WORK/rosetta-absent"    # deliberately never created

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TEST_NUM=$((TEST_NUM + 1))
    if grep -qF -- "$needle" <<<"$haystack"; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc (missing: '$needle')"
        echo "$haystack" | sed 's/^/      /' | head -5
        ALL_PASSED=false
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TEST_NUM=$((TEST_NUM + 1))
    if grep -qF -- "$needle" <<<"$haystack"; then
        print_test_result "false" "$0" "$TEST_NUM" "$desc (unexpectedly present: '$needle')"
        echo "$haystack" | sed 's/^/      /' | head -5
        ALL_PASSED=false
    else
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    fi
}

assert_exit_eq() {
    local desc="$1" expected="$2" actual="$3"
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$actual" -eq "$expected" ]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc (exit=$actual, expected=$expected)"
        ALL_PASSED=false
    fi
}

NEUTRAL_DIR="$WORK/neutral"
mkdir -p "$NEUTRAL_DIR"

# ---- Blocks when translation is detected -----------------------------------
run_launcher "$PRESENT" "$WORK/no-home" "$NEUTRAL_DIR"
assert_contains "blocks with the CPU-translation message" "$RUN_OUT" "$BLOCKED_MSG"
assert_exit_eq  "exits 1 from the guard itself"            1 "$RUN_EXIT"

# ---- Does not block on native hardware --------------------------------------
run_launcher "$ABSENT" "$WORK/no-home" "$NEUTRAL_DIR"
assert_not_contains "does not block without a translation marker" "$RUN_OUT" "$BLOCKED_MSG"

# ---- CB_ANDROID_EMULATOR_FORCE=1 bypasses the block -------------------------
# The explanation still prints either way — only the `exit 1` is skipped —
# so FORCE_MSG appearing at all is what proves it proceeded past the guard,
# not BLOCKED_MSG's absence.
run_launcher "$PRESENT" "$WORK/no-home" "$NEUTRAL_DIR" env CB_ANDROID_EMULATOR_FORCE=1
assert_contains "the force override is acknowledged, proceeding past the guard" \
    "$RUN_OUT" "$FORCE_MSG"

# ---- Names device-connect.sh when the project ships one --------------------
WITH_SCRIPT_DIR="$WORK/with-device-connect"
mkdir -p "$WITH_SCRIPT_DIR"
DEVICE_CONNECT="$WITH_SCRIPT_DIR/device-connect.sh"
: > "$DEVICE_CONNECT"
chmod +x "$DEVICE_CONNECT"
run_launcher "$PRESENT" "$WORK/no-home" "$WITH_SCRIPT_DIR"
assert_contains "names the project's device-connect.sh" "$RUN_OUT" "$DEVICE_CONNECT"

# ---- Falls back to a generic mention otherwise ------------------------------
# (this is the case a project without one — e.g. flutter-example — would hit,
# since this launcher is shared rather than android-example-specific)
run_launcher "$PRESENT" "$WORK/no-home" "$NEUTRAL_DIR"
assert_contains     "falls back to a generic real-device pointer" "$RUN_OUT" "real-device helper script"
assert_not_contains "does not invent a device-connect.sh path"    "$RUN_OUT" "device-connect.sh <ip>"

TEST_NUM=$((TEST_NUM + 1))
print_test_result "true" "$0" "$TEST_NUM" "checked the CPU-translation guard end to end"

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
