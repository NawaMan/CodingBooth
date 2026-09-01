#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# The Android SDK is present and reachable from a NON-LOGIN shell.
#
# The non-login part is the point: `booth -- ./script.sh` runs via
# `runuser -u coder --`, which never sources /etc/profile.d. A setup that only
# wires PATH through profile.d looks fine interactively and fails in every
# script, so this test deliberately does not use `bash -l`.

set -euo pipefail

# Google ships the Android SDK for linux x86_64 only; android-sdk--setup.sh
# warns and skips rather than failing the build on other architectures (see
# the "Architecture note" in this example's README). Nothing below would be
# present in that case, so skip rather than reporting a false failure.
DPKG_ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
if [[ "$DPKG_ARCH" != "amd64" ]]; then
    echo "SKIP: Android SDK is unsupported on '${DPKG_ARCH:-unknown}' (Google publishes it for linux x86_64 only)."
    exit 0
fi

echo "=== Android SDK on a non-login shell ==="

FAILED=0

for tool in sdkmanager avdmanager adb aapt2 d8 apksigner zipalign; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  ✅ $tool -> $(command -v "$tool")"
    else
        echo "  ❌ $tool NOT on PATH"
        FAILED=1
    fi
done

echo ""
echo "=== Versions (proves the binaries run, not just exist) ==="
aapt2 version || FAILED=1
adb --version | head -n1 || FAILED=1

echo ""
echo "=== android.jar for the configured API ==="
API="${ANDROID_API:-34}"
JAR="${ANDROID_SDK_ROOT:-/opt/android-sdk}/platforms/android-${API}/android.jar"
if [[ -f "$JAR" ]]; then
    echo "  ✅ $JAR"
else
    echo "  ❌ missing $JAR"
    FAILED=1
fi

echo ""
echo "=== SDK tree is readable by the booth user ==="
if [[ -r "${ANDROID_SDK_ROOT:-/opt/android-sdk}/platform-tools/adb" ]]; then
    echo "  ✅ platform-tools readable as $(id -un)"
else
    echo "  ❌ platform-tools not readable as $(id -un)"
    FAILED=1
fi

exit $FAILED
