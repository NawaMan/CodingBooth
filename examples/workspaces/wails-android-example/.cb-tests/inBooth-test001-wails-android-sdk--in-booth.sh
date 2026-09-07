#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# The Wails CLI and the Android SDK/NDK are visible from a NON-LOGIN shell.
# `booth -- ./script.sh` never sources /etc/profile.d.

set -euo pipefail

echo "=== wails3 on a non-login shell ==="

FAILED=0

if command -v wails3 >/dev/null 2>&1; then
    echo "  ✅ wails3 -> $(command -v wails3)"
else
    echo "  ❌ wails3 NOT on PATH"
    FAILED=1
fi

VERSION_OUT="$(wails3 version 2>&1 || true)"
if echo "$VERSION_OUT" | grep -qiE 'v?3\.'; then
    echo "  ✅ $VERSION_OUT"
else
    echo "  ❌ wails3 version did not report v3"
    echo "$VERSION_OUT" | sed 's/^/      /'
    FAILED=1
fi

echo ""
echo "=== Android SDK / NDK ==="

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}"
if command -v sdkmanager >/dev/null 2>&1; then
    echo "  ✅ sdkmanager -> $(command -v sdkmanager)"
elif [[ -x "${SDK}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    echo "  ✅ sdkmanager -> ${SDK}/cmdline-tools/latest/bin/sdkmanager"
else
    echo "  ❌ sdkmanager not found (ANDROID_HOME=${SDK})"
    FAILED=1
fi

NDK="${ANDROID_NDK_HOME:-}"
if [[ -z "$NDK" ]]; then
    NDK="$(ls -d "${SDK}"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi
if [[ -n "$NDK" && -d "$NDK" ]]; then
    echo "  ✅ NDK -> $NDK"
    if [[ "$NDK" == *26.3* ]]; then
        echo "  ✅ NDK is 26.3.x (what Wails' Taskfile looks for)"
    else
        echo "  ⚠️  NDK is not 26.3.x: $NDK"
    fi
else
    echo "  ❌ Android NDK not found under ${SDK}/ndk"
    FAILED=1
fi

if [[ -d "${SDK}/platforms/android-35" ]]; then
    echo "  ✅ platforms/android-35 (Wails compileSdk)"
else
    echo "  ❌ platforms/android-35 missing"
    FAILED=1
fi

echo ""
echo "=== emulator launcher ==="
if command -v cb-android-emulator >/dev/null 2>&1; then
    echo "  ✅ cb-android-emulator -> $(command -v cb-android-emulator)"
else
    echo "  ❌ cb-android-emulator NOT on PATH"
    FAILED=1
fi
if command -v emulator >/dev/null 2>&1; then
    echo "  ✅ emulator -> $(command -v emulator)"
elif [[ -x "${SDK}/emulator/emulator" ]]; then
    echo "  ✅ emulator -> ${SDK}/emulator/emulator"
else
    echo "  ❌ emulator binary not found"
    FAILED=1
fi
if [[ -f /usr/share/applications/cb-android-emulator.desktop ]]; then
    echo "  ✅ desktop entry exists"
else
    echo "  ❌ /usr/share/applications/cb-android-emulator.desktop missing (need xfce)"
    FAILED=1
fi

exit $FAILED
