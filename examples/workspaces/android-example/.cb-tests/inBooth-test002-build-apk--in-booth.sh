#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# The toolchain actually produces a signed, verifiable APK — the end-to-end
# proof that this booth can do Android work, not merely that the files are there.

set -euo pipefail

# Same arch gate as inBooth-test001: no Android SDK means no android.jar, and
# build-apk.sh cannot produce anything without it.
DPKG_ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
if [[ "$DPKG_ARCH" != "amd64" ]]; then
    echo "SKIP: Android SDK is unsupported on '${DPKG_ARCH:-unknown}' (Google publishes it for linux x86_64 only)."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Building the APK ==="
./build-apk.sh

APK="build/hello.apk"

echo ""
echo "=== Checks on the built APK ==="

FAILED=0

if [[ -f "$APK" ]]; then
    echo "  ✅ $APK exists ($(du -h "$APK" | cut -f1))"
else
    echo "  ❌ $APK was not produced"
    exit 1
fi

# A resources-only APK would still "build" — classes.dex is what proves the
# javac -> d8 leg ran.
if unzip -l "$APK" | grep -q "classes.dex"; then
    echo "  ✅ contains classes.dex"
else
    echo "  ❌ no classes.dex — the DEX step did not land"
    FAILED=1
fi

if unzip -l "$APK" | grep -q "resources.arsc"; then
    echo "  ✅ contains resources.arsc"
else
    echo "  ❌ no resources.arsc — the aapt2 link step did not land"
    FAILED=1
fi

if apksigner verify "$APK" >/dev/null 2>&1; then
    echo "  ✅ signature verifies"
else
    echo "  ❌ signature does not verify"
    FAILED=1
fi

# The manifest should carry the package we declared, proving aapt2 read it.
if aapt2 dump packagename "$APK" 2>/dev/null | grep -q "com.example.hello"; then
    echo "  ✅ package name is com.example.hello"
else
    echo "  ❌ unexpected package name: $(aapt2 dump packagename "$APK" 2>&1 | head -n1)"
    FAILED=1
fi

# An APK can build, sign and verify perfectly and still be refused by a real
# phone. Undeclared minSdk/targetSdk default to 1, and Android 14+ blocks
# installing anything targeting below API 23 — it reports "app isn't compatible
# with your phone", which reads like a hardware problem and is not one. The
# emulator installs it happily, so only these assertions catch it.
BADGING="$(aapt2 dump badging "$APK" 2>&1)"

SDK_VERSION="$(printf '%s\n' "$BADGING" | sed -n "s/^sdkVersion:'\([0-9]*\)'/\1/p")"
if [[ -n "$SDK_VERSION" ]]; then
    echo "  ✅ declares minSdkVersion $SDK_VERSION"
else
    echo "  ❌ no minSdkVersion declared — real devices will refuse to install this"
    FAILED=1
fi

TARGET_SDK="$(printf '%s\n' "$BADGING" | sed -n "s/^targetSdkVersion:'\([0-9]*\)'/\1/p")"
if [[ -n "$TARGET_SDK" ]] && (( TARGET_SDK >= 23 )); then
    echo "  ✅ declares targetSdkVersion $TARGET_SDK (>= 23, installable on Android 14+)"
else
    echo "  ❌ targetSdkVersion is '${TARGET_SDK:-unset}' — Android 14+ blocks anything below 23"
    FAILED=1
fi

if printf '%s\n' "$BADGING" | grep -q "versionCode='[0-9]"; then
    echo "  ✅ carries a versionCode"
else
    echo "  ❌ no versionCode — upgrades and store tooling need one"
    FAILED=1
fi

exit $FAILED
