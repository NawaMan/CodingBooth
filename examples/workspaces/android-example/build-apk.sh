#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Build a signed, installable APK using only the Android SDK build-tools —
# no Gradle, no Android Gradle Plugin, no network.
#
# Gradle would be the normal choice for a real app, but it resolves AGP and its
# dependency tree from the network on first run, which makes it a poor proof
# that *this booth's toolchain* works. Driving aapt2/javac/d8/apksigner directly
# is the same pipeline AGP drives, minus the download.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_DIR="app"
OUT_DIR="build"
API="${ANDROID_API:-34}"

# minSdk/targetSdk are NOT optional metadata — they decide whether a real phone
# will install the APK at all. Left undeclared, targetSdkVersion defaults to
# minSdkVersion, which defaults to 1, and Android 14+ refuses to install anything
# targeting below API 23 ("app isn't compatible with your phone", or
# INSTALL_FAILED_DEPRECATED_SDK_VERSION over adb). The emulator is more
# permissive, so this only shows up on real hardware.
#
# AGP injects these into the merged manifest; driving aapt2 directly means
# passing them by hand.
MIN_SDK="${MIN_SDK:-24}"
TARGET_SDK="${TARGET_SDK:-$API}"
VERSION_CODE="${VERSION_CODE:-1}"
VERSION_NAME="${VERSION_NAME:-1.0}"

SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
ANDROID_JAR="${SDK_ROOT}/platforms/android-${API}/android.jar"

# jdk--setup.sh registers keytool with update-alternatives, so it is on PATH even
# in the non-login shell `booth -- ./build-apk.sh` runs in. The fallbacks below
# are kept deliberately: they let this script also work against an older base
# image built before keytool joined that list, where PATH alone would not find it.
# /opt/jdk is the version-independent link the JDK setup leaves.
KEYTOOL="$(command -v keytool || true)"
for candidate in "${JAVA_HOME:-}/bin/keytool" /opt/jdk/bin/keytool; do
    [[ -n "$KEYTOOL" ]] && break
    [[ -x "$candidate" ]] && KEYTOOL="$candidate"
done
if [[ -z "$KEYTOOL" ]]; then
    echo "❌ keytool not found (looked on PATH, in \$JAVA_HOME/bin, and /opt/jdk/bin)"
    exit 1
fi

if [[ ! -f "$ANDROID_JAR" ]]; then
    echo "❌ No android.jar for API ${API} at ${ANDROID_JAR}"
    echo "   Is this running inside the booth? Try: booth -- ./build-apk.sh"
    exit 1
fi

# Every stage before signing is an intermediate, and the two that happen to be
# .apk files (the aapt2 link output, and its zipaligned copy) are NOT installable
# — Android rejects an unsigned APK with INSTALL_PARSE_FAILED_NO_CERTIFICATES.
# They live under build/intermediates/ so that build/ holds exactly one .apk: the
# one you can actually install. Same split AGP makes between intermediates/ and
# outputs/.
INT_DIR="$OUT_DIR/intermediates"

rm -rf "$OUT_DIR"
mkdir -p "$INT_DIR"/{res,classes,dex,gen}

echo "==> aapt2 compile (resources)"
aapt2 compile --dir "$APP_DIR/res" -o "$INT_DIR/res/resources.zip"

echo "==> aapt2 link (resource table + R.java)"
aapt2 link \
    -I "$ANDROID_JAR" \
    --manifest "$APP_DIR/AndroidManifest.xml" \
    --min-sdk-version "$MIN_SDK" \
    --target-sdk-version "$TARGET_SDK" \
    --version-code "$VERSION_CODE" \
    --version-name "$VERSION_NAME" \
    --java "$INT_DIR/gen" \
    -o "$INT_DIR/unsigned.apk" \
    "$INT_DIR/res/resources.zip"

echo "==> javac (sources + generated R.java)"
# aapt2 wrote R.java under gen/<package path>/, so the glob picks it up.
javac -source 8 -target 8 -nowarn \
    -bootclasspath "$ANDROID_JAR" \
    -classpath "$ANDROID_JAR" \
    -d "$INT_DIR/classes" \
    $(find "$APP_DIR/src" "$INT_DIR/gen" -name '*.java')

echo "==> d8 (JVM bytecode -> DEX)"
d8 --lib "$ANDROID_JAR" \
    --output "$INT_DIR/dex" \
    $(find "$INT_DIR/classes" -name '*.class')

echo "==> package DEX into the APK"
# The APK from aapt2 link holds resources only; classes.dex has to be added at
# the archive root, which is what the -j (junk paths) flag guarantees.
(cd "$INT_DIR" && zip -q -j unsigned.apk dex/classes.dex)

echo "==> zipalign"
# Alignment has to happen BEFORE signing: zipalign rewrites offsets, which would
# invalidate a signature already in the archive.
zipalign -f 4 "$INT_DIR/unsigned.apk" "$INT_DIR/aligned.apk"

echo "==> keystore (debug, generated on first build)"
KEYSTORE="$INT_DIR/debug.keystore"
if [[ ! -f "$KEYSTORE" ]]; then
    "$KEYTOOL" -genkeypair -v \
        -keystore "$KEYSTORE" \
        -storepass android -keypass android \
        -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US" > /dev/null 2>&1
fi

echo "==> apksigner"
apksigner sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out "$OUT_DIR/hello.apk" \
    "$INT_DIR/aligned.apk"

echo "==> verify"
apksigner verify --verbose "$OUT_DIR/hello.apk" | head -n 5

echo ""
echo "✅ Built $OUT_DIR/hello.apk ($(du -h "$OUT_DIR/hello.apk" | cut -f1))"
echo "   Install on a running emulator or device with:  adb install -r $OUT_DIR/hello.apk"
echo ""
echo "   $OUT_DIR/intermediates/ holds the unsigned stages (unsigned.apk, aligned.apk)."
echo "   Those cannot be installed — Android rejects an unsigned APK."
