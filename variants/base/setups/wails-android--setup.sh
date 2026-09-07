#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# wails-android--setup.sh
# Installs the Android NDK and API 35 platform Wails v3's Gradle file compiles
# against, so `wails3 task android:build` can produce an APK.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Run after wails--setup.sh and android-sdk--setup.sh; skips cleanly if the
  SDK is missing, so a booth without it still builds.
- Wails' template pins compileSdk/targetSdk 35 and looks for NDK 26.3.x
  (see build/android/Taskfile.yml). A stock android-sdk install is API 34
  and has no NDK, so the Gradle task fails without this.
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
if [[ -r "$SCRIPT_DIR/libs/skip-setup.sh" ]]; then
  source "$SCRIPT_DIR/libs/skip-setup.sh"
else
  source "${SETUP_LIBS_DIR}/skip-setup.sh"
fi

ANDROID_SDK_DIR=/opt/android-sdk
# Pin matches the version Wails' Android Taskfile tells you to install.
NDK_VERSION="26.3.11579264"
ANDROID_API="35"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

SDKMANAGER="${ANDROID_SDK_DIR}/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$SDKMANAGER" ]]; then
  skip_setup "$SCRIPT_NAME" "Android SDK not found at ${ANDROID_SDK_DIR}"
fi

# android-sdk already skipped on arm64; match that so this layer does not fail
# the image.
dpkgArch="$(dpkg --print-architecture)"
if [[ "$dpkgArch" != "amd64" ]]; then
  skip_setup "$SCRIPT_NAME" "Android NDK is published for linux x86_64 only (host is ${dpkgArch})"
fi

export ANDROID_SDK_ROOT="$ANDROID_SDK_DIR"
export ANDROID_HOME="$ANDROID_SDK_DIR"

# Licenses were accepted in android-sdk--setup.sh; NDK/API 35 can introduce
# extra ones. `yes | --licenses` exits non-zero when stdin dries up — expected.
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

# Do not pipe `yes` into --install: under `set -o pipefail` `yes` dies with
# SIGPIPE when sdkmanager closes stdin, and the layer fails even if the
# packages installed. android-sdk--setup.sh and android-emulator--setup.sh
# call --install the same way.
echo "Installing Android NDK ${NDK_VERSION} and platforms;android-${ANDROID_API} ..."
"$SDKMANAGER" --install \
  "ndk;${NDK_VERSION}" \
  "platforms;android-${ANDROID_API}"

NDK_HOME="${ANDROID_SDK_DIR}/ndk/${NDK_VERSION}"
if [[ ! -d "$NDK_HOME" ]]; then
  echo "❌ NDK did not land at ${NDK_HOME}" >&2
  exit 1
fi
chmod -R a+rX "$NDK_HOME" "${ANDROID_SDK_DIR}/platforms/android-${ANDROID_API}"

# Login shells get ANDROID_NDK_HOME. just build-android also exports it so a
# non-login `booth -- just build-android` sees the same path.
cat >/etc/profile.d/67-cb-wails-android--profile.sh <<EOF
# NDK Wails compiles libwails.so with
export ANDROID_NDK_HOME=${NDK_HOME}
EOF
chmod 0644 /etc/profile.d/67-cb-wails-android--profile.sh

echo "✅ Wails Android NDK ${NDK_VERSION} and API ${ANDROID_API} installed."
cat <<EON
ℹ️ Ready to use:
  wails3 task android:build
  wails3 task android:assemble:apk    # debug APK → bin/<app>.apk
  just build-android                  # same, from the example Justfile
EON
