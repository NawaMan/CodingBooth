#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the avd-cache extension actually persists the emulator's device, and
# cb-android-emulator-stop is what makes it persist.
#
# This is the one claim about avd-cache that cannot be checked from inside a
# booth: proving state survives requires a SECOND container, so the whole test is
# host-side and starts the booth twice.
#
# It is also the claim most likely to rot silently. The emulator does not write a
# Quick Boot snapshot on its own way out — neither `adb emu kill` nor a SIGTERM
# leaves one — so if cb-android-emulator-stop ever stops saving, every other test
# still passes and users simply lose their device on each restart, with no error
# anywhere. Hence: write a marker, stop properly, restart, read it back.
#
# GATED. Two Android boots is minutes, not seconds:
#   CB_ANDROID_EMULATOR_TEST=1 ./test--avd-persistence.sh
# -----------------------------------------------------------------------------

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: avd-cache persists the device across booth restarts ==="

if [[ "${CB_ANDROID_EMULATOR_TEST:-0}" != "1" ]]; then
    echo "SKIP: set CB_ANDROID_EMULATOR_TEST=1 to run (two Android boots)."
    exit 0
fi

use_local_base_image || exit 0

# Locate the repo root, for the binary and the templates the extension lives in.
REPO_ROOT="$SCRIPT_DIR"
for _ in 1 2 3 4 5; do
    [[ -f "$REPO_ROOT/codingbooth" && -x "$REPO_ROOT/codingbooth" ]] && break
    REPO_ROOT="$(dirname "$REPO_ROOT")"
done
if [[ ! -x "$REPO_ROOT/codingbooth" ]]; then
    echo "ERROR: Could not find codingbooth"
    exit 1
fi
BOOTH="$REPO_ROOT/codingbooth"

# A throwaway project, because the cache grows to gigabytes and must not be left
# in the repo. Generated through the real template so the mount under test is the
# one `booth config --select +avd-cache` actually produces.
PRJ="$(mktemp -d)"
cleanup() {
    docker rm -f "$(basename "$PRJ")" >/dev/null 2>&1 || true
    rm -rf "$PRJ"
}
trap cleanup EXIT

"$BOOTH" config "$PRJ" --no-tui --overwrite \
    --templates-path "$REPO_ROOT/templates" \
    --variant base --port 50419 \
    --select "java:17/android-sdk+emulator+kvm+avd-cache" >/dev/null 2>&1

FAILED=0

if [[ -d "$PRJ/.booth/cache/home/coder/.android" ]]; then
    print_test_result "true" "$0" "1" "avd-cache generates the ~/.android cache mount"
else
    print_test_result "false" "$0" "1" "avd-cache should generate the ~/.android cache mount"
    exit 1
fi

MARKER="cb-persist-$$"

# --- session 1: boot, write a marker, stop the documented way -----------------
cat > "$PRJ/s1.sh" <<EOF
#!/bin/bash
cb-android-emulator -no-window > /tmp/e.log 2>&1 &
adb wait-for-device
for i in \$(seq 1 60); do
    [ "\$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
    sleep 5
done
adb shell 'echo ${MARKER} > /sdcard/cb-persist.txt'
adb shell cat /sdcard/cb-persist.txt | tr -d '\r'
cb-android-emulator-stop
EOF
chmod +x "$PRJ/s1.sh"

S1=$("$BOOTH" --code "$PRJ" --silence-build -- ./s1.sh 2>&1)
if echo "$S1" | grep -q "$MARKER" && echo "$S1" | grep -q "State saved"; then
    print_test_result "true" "$0" "2" "session 1 wrote the marker and cb-android-emulator-stop saved state"
else
    print_test_result "false" "$0" "2" "session 1 should write the marker and save state"
    echo "$S1" | tail -n 8
    exit 1
fi

docker rm -f "$(basename "$PRJ")" >/dev/null 2>&1 || true

# --- session 2: a brand new container must still see the marker ---------------
cat > "$PRJ/s2.sh" <<'EOF'
#!/bin/bash
cb-android-emulator -no-window > /tmp/e.log 2>&1 &
adb wait-for-device
for i in $(seq 1 60); do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
    sleep 5
done
echo "MARKER_READBACK=$(adb shell cat /sdcard/cb-persist.txt 2>/dev/null | tr -d '\r')"
adb emu kill >/dev/null 2>&1
EOF
chmod +x "$PRJ/s2.sh"

S2=$("$BOOTH" --code "$PRJ" --silence-build -- ./s2.sh 2>&1)
if echo "$S2" | grep -q "MARKER_READBACK=${MARKER}"; then
    print_test_result "true" "$0" "3" "device state survived into a new container"
else
    print_test_result "false" "$0" "3" "device state should survive into a new container"
    echo "$S2" | grep -E "MARKER_READBACK|error|Error" | tail -n 5
    FAILED=$((FAILED + 1))
fi

# A stale lock from session 1's container exit must not block session 2 — that
# failure looks like "a snapshot operation is pending" and bricks every restart.
if echo "$S2" | grep -qi "snapshot operation.*pending"; then
    print_test_result "false" "$0" "4" "a stale lock must not block the next start"
    FAILED=$((FAILED + 1))
else
    print_test_result "true" "$0" "4" "no stale-lock failure on the second start"
fi

exit $FAILED
