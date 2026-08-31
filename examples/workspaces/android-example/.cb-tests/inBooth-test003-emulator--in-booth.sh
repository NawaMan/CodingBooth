#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Boot the emulator, install the APK, and confirm the app actually comes to the
# foreground — the one thing building an APK cannot tell you.
#
# GATED, and deliberately so. Booting Android is slow enough to dominate an
# otherwise ~1-minute example run: measured here, ~20s with KVM and ~258s
# without (software emulation is roughly 13x slower to boot). So it runs by
# default only where that is cheap — KVM present, not under CI — and is
# turned off explicitly rather than left off by default:
#
#   CB_ANDROID_EMULATOR_TEST=0 ./run-automatic-on-host-test.sh   # skip it
#   CB_ANDROID_EMULATOR_TEST=1 ./run-automatic-on-host-test.sh   # force it
#
# It adapts to the host rather than requiring KVM: with /dev/kvm it boots
# hardware-accelerated, without it falls back to -accel off. The fallback is not
# automatic in the emulator itself — unaccelerated it refuses to start outright
# with "x86_64 emulation currently requires hardware acceleration!" — so the flag
# has to be chosen here.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Opt-out, not opt-in: a booth that can afford this should run it. =1 forces it
# on, =0 turns it off, and unset means "run if this booth can" — which is CI off,
# and off where /dev/kvm is not usable, since software emulation turns a ~20s
# boot into ~258s. The on-host runner normally decides and passes an explicit
# value; this stands on its own for anyone running the script directly.
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

if ! command -v emulator >/dev/null 2>&1; then
    echo "SKIP: no emulator in this booth — reconfigure with +emulator to enable it."
    exit 0
fi

APK="build/hello.apk"
if [[ ! -f "$APK" ]]; then
    echo "=== APK not built yet; building it first ==="
    ./build-apk.sh >/dev/null || { echo "❌ build-apk.sh failed"; exit 1; }
fi

# The launcher derives the system image from whatever is installed, so this test
# does not name one — that derivation is part of what is under test.
AVD_NAME="cb-test"

FAILED=0

echo "=== Desktop launcher ==="
# The icon is how most people will start this, so a broken launcher is a broken
# feature even when `emulator` itself works.
if command -v cb-android-emulator >/dev/null 2>&1; then
    echo "  ✅ cb-android-emulator is on PATH"
else
    echo "  ❌ cb-android-emulator is missing"
    FAILED=1
fi

DESKTOP_ENTRY=/usr/share/applications/cb-android-emulator.desktop
if [[ -f "$DESKTOP_ENTRY" ]]; then
    echo "  ✅ start menu entry exists"
    # An Exec= pointing at something absent is the classic dead launcher.
    EXEC_BIN="$(sed -n 's/^Exec=//p' "$DESKTOP_ENTRY" | head -1 | awk '{print $1}')"
    if [[ -x "$EXEC_BIN" ]]; then
        echo "  ✅ its Exec target is executable ($EXEC_BIN)"
    else
        echo "  ❌ its Exec target is not executable: $EXEC_BIN"
        FAILED=1
    fi
    ICON="$(sed -n 's/^Icon=//p' "$DESKTOP_ENTRY" | head -1)"
    if [[ -f "$ICON" ]]; then
        echo "  ✅ its icon file exists ($ICON)"
    else
        echo "  ❌ its icon file is missing: $ICON"
        FAILED=1
    fi
else
    echo "  ❌ $DESKTOP_ENTRY is missing"
    FAILED=1
fi

echo "=== Boot via the real launcher ==="
# Deliberately go through cb-android-emulator rather than calling avdmanager and
# emulator directly. The launcher is what the desktop icon runs and what creates
# the AVD, so driving it here is the only way the AVD's hardware profile gets
# tested at all — see the config assertions below.
rm -rf "$HOME/.android/avd/${AVD_NAME}"* 2>/dev/null || true
START=$(date +%s)
CB_AVD_NAME="$AVD_NAME" nohup cb-android-emulator \
    -no-window -no-audio -no-snapshot -no-metrics > /tmp/emulator.log 2>&1 &

# adb wait-for-device returns as soon as the daemon SEES the device, which is
# long before Android is usable. sys.boot_completed is the real gate.
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

echo "=== AVD hardware profile ==="
# The regression this guards: created without a device profile, the AVD gets
# hw.mainKeys=yes — "this device has physical Back/Home keys, so do not draw the
# on-screen navigation bar". An emulator window has no physical keys, so nothing
# draws them and nothing responds; the app cannot be left. hw.keyboard=no is the
# same trap for typing. Both are silent: the emulator boots and the app runs.
#
# The emulator rewrites config.ini as "key = value" on first boot while
# avdmanager writes "key=value", so these patterns tolerate the spacing.
AVD_CONFIG="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
if [[ -f "$AVD_CONFIG" ]]; then
    if grep -qE '^hw\.mainKeys *= *no' "$AVD_CONFIG"; then
        echo "  ✅ hw.mainKeys=no — the on-screen navigation bar is drawn"
    else
        echo "  ❌ hw.mainKeys is not 'no' — there would be no Back/Home button"
        grep -E '^hw\.mainKeys' "$AVD_CONFIG" || echo "     (key absent)"
        FAILED=1
    fi

    if grep -qE '^hw\.keyboard *= *yes' "$AVD_CONFIG"; then
        echo "  ✅ hw.keyboard=yes — the host keyboard reaches the guest"
    else
        echo "  ❌ hw.keyboard is not 'yes' — you could tap but not type"
        FAILED=1
    fi

    if grep -qE '^hw\.device\.name *= *.+' "$AVD_CONFIG"; then
        echo "  ✅ a device profile is set ($(sed -n 's/^hw\.device\.name *= *//p' "$AVD_CONFIG" | head -1))"
    else
        echo "  ❌ no device profile — the AVD falls back to a 320x640 mdpi screen"
        FAILED=1
    fi
else
    echo "  ❌ no config.ini at $AVD_CONFIG — the launcher did not create the AVD"
    FAILED=1
fi

echo "=== Install ==="
if adb install -r "$APK" 2>&1 | grep -q "Success"; then
    echo "  ✅ adb install succeeded"
else
    echo "  ❌ adb install failed"
    adb install -r "$APK" 2>&1 | tail -n 5
    FAILED=1
fi

# Installed is not the same as installed-and-visible-to-the-package-manager.
if adb shell pm list packages 2>/dev/null | grep -q "com.example.hello"; then
    echo "  ✅ package manager lists com.example.hello"
else
    echo "  ❌ com.example.hello is not registered with the package manager"
    FAILED=1
fi

echo "=== Launch ==="
adb shell monkey -p com.example.hello -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5

# The real assertion: the Activity reached the foreground. An APK can install
# and still crash on start (a bad minSdk, a missing class, a broken DEX).
if adb shell dumpsys activity activities 2>/dev/null | grep -q "topResumedActivity.*com.example.hello/.MainActivity"; then
    echo "  ✅ MainActivity is the resumed foreground activity"
else
    echo "  ❌ MainActivity did not reach the foreground"
    adb shell dumpsys activity activities 2>/dev/null | grep -i "com.example.hello" | head -n 3
    FAILED=1
fi

# A crash would be in logcat even if the activity briefly showed.
if adb logcat -d -b crash 2>/dev/null | grep -q "com.example.hello"; then
    echo "  ❌ the app appears in the crash buffer"
    adb logcat -d -b crash 2>/dev/null | grep -A5 "com.example.hello" | head -n 10
    FAILED=1
else
    echo "  ✅ nothing from com.example.hello in the crash buffer"
fi

echo "=== Stop command ==="
if command -v cb-android-emulator-stop >/dev/null 2>&1; then
    echo "  ✅ cb-android-emulator-stop is on PATH"
else
    echo "  ❌ cb-android-emulator-stop is missing — device state could not be saved"
    FAILED=1
fi

echo "=== Recipe stamp ==="
STAMP="$HOME/.android/avd/${AVD_NAME}.avd/.cb-recipe"
if [[ -s "$STAMP" ]]; then
    echo "  ✅ AVD carries a recipe stamp ($(cat "$STAMP"))"
else
    echo "  ❌ no recipe stamp — a cached AVD could outlive a launcher fix"
    FAILED=1
fi

echo "=== Shut the emulator down ==="
adb emu kill >/dev/null 2>&1 || true
sleep 3

# The stamp only earns its keep if a stale one forces a rebuild. Without this the
# avd-cache extension would preserve a broken device forever — which is exactly
# how an AVD built before the device-profile fix would have kept its unusable
# hw.mainKeys=yes. Cheap to check: corrupt the stamp and restart.
echo "=== Stale stamp forces a rebuild ==="
printf '0:stale-device:stale-image\n' > "$STAMP"
CB_AVD_NAME="$AVD_NAME" nohup cb-android-emulator \
    -no-window -no-audio -no-snapshot -no-metrics > /tmp/emulator-rebuild.log 2>&1 &
REBUILT=""
for _ in $(seq 1 30); do
    [[ "$(cat "$STAMP" 2>/dev/null)" != "0:stale-device:stale-image" ]] && { REBUILT=1; break; }
    sleep 5
done
if [[ -n "$REBUILT" ]]; then
    echo "  ✅ stale stamp triggered a rebuild (now $(cat "$STAMP"))"
    if grep -qE '^hw\.mainKeys *= *no' "$AVD_CONFIG"; then
        echo "  ✅ the rebuilt AVD has the corrected profile"
    else
        echo "  ❌ the rebuilt AVD is still misconfigured"
        FAILED=1
    fi
else
    echo "  ❌ a stale stamp did not trigger a rebuild"
    grep -m2 -i "recipe" /tmp/emulator-rebuild.log || true
    FAILED=1
fi
adb emu kill >/dev/null 2>&1 || true

echo "=== Total: $(( $(date +%s) - START ))s ==="
exit $FAILED
