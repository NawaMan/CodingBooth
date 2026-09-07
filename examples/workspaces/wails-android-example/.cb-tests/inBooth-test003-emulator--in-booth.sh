#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Boot the emulator, install the Wails APK, confirm MainActivity is foreground.
# Gated like android-example: default on when KVM is usable and this is not CI.
#
#   CB_ANDROID_EMULATOR_TEST=0   skip
#   CB_ANDROID_EMULATOR_TEST=1   force (including software emulation)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

case "${CB_ANDROID_EMULATOR_TEST:-}" in
    1|true|yes|on)  ;;
    0|false|no|off)
        echo "SKIP: CB_ANDROID_EMULATOR_TEST is off."
        exit 0
        ;;
    *)
        if [[ -n "${CI:-}" ]]; then
            echo "SKIP: running under CI — set CB_ANDROID_EMULATOR_TEST=1 to run it here anyway."
            exit 0
        fi
        if [[ ! -c /dev/kvm || ! -r /dev/kvm || ! -w /dev/kvm ]]; then
            echo "SKIP: no usable /dev/kvm in this booth — the emulator would boot roughly 13x slower. Set CB_ANDROID_EMULATOR_TEST=1 to run anyway."
            exit 0
        fi
        ;;
esac

if ! command -v emulator >/dev/null 2>&1 && ! command -v cb-android-emulator >/dev/null 2>&1; then
    echo "SKIP: no emulator in this booth."
    exit 0
fi

APK="bin/booth-counter.apk"
if [[ ! -f "$APK" ]]; then
    echo "=== APK not built yet; building it first ==="
    just build >/dev/null || { echo "❌ just build failed"; exit 1; }
fi

AVD_NAME="cb-test"
FAILED=0
PKG="com.wails.app"

echo "=== Boot via cb-android-emulator ==="
rm -rf "$HOME/.android/avd/${AVD_NAME}"* 2>/dev/null || true
START=$(date +%s)
CB_AVD_NAME="$AVD_NAME" nohup cb-android-emulator \
    -no-window -no-audio -no-snapshot -no-metrics > /tmp/emulator.log 2>&1 &

adb wait-for-device
BOOTED=""
for _ in $(seq 1 180); do
    BOOTED="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$BOOTED" == "1" ]] && break
    sleep 10
done

if [[ "$BOOTED" != "1" ]]; then
    echo "  ❌ did not finish booting within $(( $(date +%s) - START ))s"
    tail -n 15 /tmp/emulator.log
    exit 1
fi
echo "  ✅ booted in $(( $(date +%s) - START ))s"

echo "=== Install ==="
if adb install -r "$APK" 2>&1 | grep -q "Success"; then
    echo "  ✅ adb install succeeded"
else
    echo "  ❌ adb install failed"
    adb install -r "$APK" 2>&1 | tail -n 5
    FAILED=1
fi

if adb shell pm list packages 2>/dev/null | grep -q "$PKG"; then
    echo "  ✅ package manager lists $PKG"
else
    echo "  ❌ $PKG is not registered with the package manager"
    FAILED=1
fi

echo "=== Launch ==="
adb shell am start -n "${PKG}/.MainActivity" >/dev/null 2>&1
sleep 5

if adb shell dumpsys activity activities 2>/dev/null | grep -q "topResumedActivity.*${PKG}/.MainActivity\|topResumedActivity.*${PKG}/com.wails.app.MainActivity"; then
    echo "  ✅ MainActivity is the resumed foreground activity"
else
    echo "  ❌ MainActivity did not reach the foreground"
    adb shell dumpsys activity activities 2>/dev/null | grep -i "$PKG" | head -n 3
    FAILED=1
fi

exit $FAILED
