#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# flutter-android--setup.sh
# Points Flutter at the Android SDK and precaches the Android engine artifacts,
# so `flutter build apk` works instead of asking for an SDK it cannot find.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--android-sdk <path>]

Notes:
- Run after flutter--setup.sh and android-sdk--setup.sh; skips cleanly if either
  is missing, so a booth without them still builds.
- Writes /etc/cb-flutter.d/50-android.sh, which both the profile and the
  flutter/dart wrappers pick up -- that is what makes the SDK visible to a
  non-login shell such as 'booth -- ./gradlew assembleDebug'.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ This script must be run as root (use sudo)" >&2; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

# A script copied into a project's .booth/setups/ shadows the image's copy, but
# libs/ does not come with it -- so $SCRIPT_DIR/libs is simply absent on the very
# path the dev loop and the complex tests use.
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
if [[ -r "$SCRIPT_DIR/libs/skip-setup.sh" ]]; then
    source "$SCRIPT_DIR/libs/skip-setup.sh"
else
    source "${SETUP_LIBS_DIR}/skip-setup.sh"
fi

ANDROID_SDK_DIR=/opt/android-sdk

while [[ $# -gt 0 ]]; do
  case "$1" in
    --android-sdk) shift; ANDROID_SDK_DIR="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- guards ----
# Both prerequisites bail out on arm64 by design, so this one has to as well --
# and it must skip rather than fail, or every arm64 build breaks here.
if ! command -v flutter >/dev/null 2>&1; then
  skip_setup "$SCRIPT_NAME" "Flutter not installed (run flutter--setup.sh first)"
fi
if [[ ! -x "${ANDROID_SDK_DIR}/cmdline-tools/latest/bin/sdkmanager" ]]; then
  skip_setup "$SCRIPT_NAME" "Android SDK not found at ${ANDROID_SDK_DIR}"
fi

export FLUTTER_SUPPRESS_ANALYTICS=true
export ANDROID_SDK_ROOT="$ANDROID_SDK_DIR"
export ANDROID_HOME="$ANDROID_SDK_DIR"

# ---- environment drop-in ----
# 'flutter config --android-sdk' would look like the obvious move, but it writes
# to $HOME/.config/flutter/settings -- root's, at build time -- and the booth
# runs as coder, so the setting would be invisible to the person who needs it.
# The env vars are read by every Flutter version and are user-independent.
install -d /etc/cb-flutter.d
cat >/etc/cb-flutter.d/50-android.sh <<EOF
# Android SDK, for Flutter's Android toolchain
export ANDROID_SDK_ROOT="${ANDROID_SDK_DIR}"
export ANDROID_HOME="${ANDROID_SDK_DIR}"
EOF
chmod 0644 /etc/cb-flutter.d/50-android.sh

# Login shells read profile.d rather than the wrappers, so the same values go
# there too. Order 67: after flutter (61) and the Android SDK (63).
cat >/etc/profile.d/67-cb-flutter-android--profile.sh <<'EOF'
# Profile: Flutter Android target
[ -r /etc/cb-flutter.d/50-android.sh ] && . /etc/cb-flutter.d/50-android.sh
EOF
chmod 0644 /etc/profile.d/67-cb-flutter-android--profile.sh

# ---- the platform Flutter compiles against ----
# android-sdk's default API is not necessarily the one Flutter needs: an app
# compiles against the SDK named in the Flutter SDK's own gradle plugin, and a
# mismatch fails the Gradle task with "Flutter requires Android SDK <N>" -- so
# `flutter+android` on stock defaults would produce a booth that builds nothing.
# Rather than pin a number here that rots on the next Flutter release, read it
# from whichever Flutter is actually installed and install that platform if the
# SDK does not already have it. The user's ANDROID_API pin is left alone; this
# only ever adds.
FLUTTER_DIR="$(readlink -f /usr/local/flutter-current)"
EXT_KT="${FLUTTER_DIR}/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
COMPILE_SDK=""
if [[ -r "$EXT_KT" ]]; then
  COMPILE_SDK="$(grep -oE 'compileSdkVersion: *Int *= *[0-9]+' "$EXT_KT" | grep -oE '[0-9]+$' || true)"
fi

if [[ -n "$COMPILE_SDK" ]]; then
  if [[ -d "${ANDROID_SDK_DIR}/platforms/android-${COMPILE_SDK}" ]]; then
    echo "Flutter compiles against Android ${COMPILE_SDK}; that platform is already installed."
  else
    echo "Flutter compiles against Android ${COMPILE_SDK}; installing that platform ..."
    "${ANDROID_SDK_DIR}/cmdline-tools/latest/bin/sdkmanager" \
      --install "platforms;android-${COMPILE_SDK}" > /dev/null
    # Installed by root, read by coder — same rule as the SDK itself.
    chmod -R a+rX "${ANDROID_SDK_DIR}/platforms"
  fi
else
  echo "⚠️  Could not read Flutter's compileSdkVersion from ${EXT_KT}."
  echo "    If 'flutter build apk' reports a missing Android SDK, re-select android-sdk"
  echo "    with a matching --api."
fi

# ---- engine artifacts ----
# Without this the first 'flutter build apk' stops to download a few hundred
# megabytes of Android engine artifacts, which is exactly the stall the base
# setup's precache exists to avoid.
echo "Fetching the Flutter Android engine artifacts ..."
flutter precache --android > /dev/null

# ---- licenses ----
# android-sdk--setup.sh already accepted the SDK licenses, so this normally has
# nothing to do; it is here because Flutter checks for its own record of them and
# reports a doctor failure when it is missing. Exits non-zero once stdin runs
# dry, which is expected.
yes | flutter doctor --android-licenses > /dev/null 2>&1 || true

# ---- summary ----
# Before the permission pass, not after: `flutter doctor` rewrites bin/cache as
# root, and anything root touches after the chmod stays root-owned and 0644 --
# which at runtime turns the tool's own `mv` of a stamp file into an
# unanswerable prompt that hangs with no output.
echo "✅ Flutter Android toolchain wired to ${ANDROID_SDK_DIR}."
flutter doctor 2>/dev/null | grep -iE "android tool|android studio" || true

# ---- permissions (must be last) ----
# precache and doctor wrote into the SDK tree as root; re-open it for the user.
chmod -R a+rwX "${FLUTTER_DIR}/bin/cache"

# Flutter builds through Gradle, and Gradle installs SDK components on demand --
# the NDK named by the app's build.gradle.kts, most often. android-sdk--setup.sh
# leaves the tree read-only (a+rX), which is right for its own aapt2/d8 path but
# makes every such install fail with "The SDK directory is not writable", and the
# APK build dies in project configuration before compiling a line.
#
# Relaxed here rather than in android-sdk--setup.sh on purpose: this is a cost of
# the Gradle path, so only booths that opted into `flutter+android` pay it, and
# the Android SDK keeps the tighter mode for everyone else. Mode bits, not chown,
# for the usual reason -- booth-entry remaps the booth user's UID at start.
echo "Making the Android SDK writable, so Gradle can install components it needs ..."
chmod -R a+rwX "$ANDROID_SDK_DIR"

cat <<'EON'
Ready to use:
- Build a debug APK:  flutter build apk --debug
- List devices:       flutter devices
- With the android-sdk 'emulator' extension selected, start one first:
      cb-android-emulator &      # then: flutter run
EON
