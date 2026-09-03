#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--cmdline-tools <build>] [--api <level>] [--build-tools <version>] [--no-platform]

Examples:
  $0                                    # cmdline-tools + platform-tools + API 34 + build-tools 34.0.0
  $0 --api 35 --build-tools 35.0.0      # a different platform
  $0 --no-platform                      # sdkmanager and adb only, no platform/build-tools

Notes:
- SDK root is /opt/android-sdk; ANDROID_SDK_ROOT and ANDROID_HOME point at it.
- Requires a JDK (sdkmanager is a Java program) — run jdk--setup.sh first.
- The emulator and its system image are a separate, much larger install:
  see android-emulator--setup.sh.
- Google ships platform-tools and build-tools for linux x86_64 only, so on arm64
  this warns and skips rather than failing the build.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ This script must be run as root (use sudo)" >&2; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
# Pinned so an image rebuild cannot silently change the toolchain under the app.
CMDLINE_TOOLS="11076708"
ANDROID_API="34"
BUILD_TOOLS="34.0.0"
WITH_PLATFORM=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cmdline-tools) shift; CMDLINE_TOOLS="${1:-}"; shift ;;
    --api)           shift; ANDROID_API="${1:-}";   shift ;;
    --build-tools)   shift; BUILD_TOOLS="${1:-}";   shift ;;
    --no-platform)   WITH_PLATFORM=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

SDK_ROOT=/opt/android-sdk
SDKMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
BIN_DIR=/usr/local/bin

# ---- arch gate ----
# cmdline-tools is pure Java, but everything it would install below (adb, aapt2,
# d8) is published for linux x86_64 only. Warn and skip rather than fail: the
# image still builds, the tool is simply absent. Same contract as
# unsupported-arch in the template.
dpkgArch="$(dpkg --print-architecture)"
if [[ "$dpkgArch" != "amd64" ]]; then
  echo "⚠️  The Android SDK command-line tools are published for linux x86_64 only."
  echo "    Host architecture is '${dpkgArch}' — skipping the Android SDK install."
  exit 0
fi

# ---- java check ----
if ! command -v java >/dev/null 2>&1; then
  echo "❌ sdkmanager needs a JDK on PATH, and none was found." >&2
  echo "   Run 'setup jdk' before 'setup android-sdk' (Boothfile order 50 vs 60)." >&2
  exit 1
fi

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip
rm -rf /var/lib/apt/lists/*

# ---- command-line tools ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLT_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip"

echo "Downloading Android command-line tools ${CMDLINE_TOOLS} ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$CLT_URL" -o "$TMP/cmdline-tools.zip"

echo "Installing Android command-line tools ..."
# sdkmanager insists on living at cmdline-tools/latest/; the zip unpacks to a
# plain cmdline-tools/, so the move is not cosmetic.
rm -rf "${SDK_ROOT}/cmdline-tools"
mkdir -p "${SDK_ROOT}/cmdline-tools"
unzip -q "$TMP/cmdline-tools.zip" -d "${SDK_ROOT}/cmdline-tools"
mv "${SDK_ROOT}/cmdline-tools/cmdline-tools" "${SDK_ROOT}/cmdline-tools/latest"

# ---- licenses ----
# Non-interactive builds cannot answer the prompts, and sdkmanager refuses to
# install anything until they are accepted. It exits non-zero once stdin runs
# dry, which is expected here and not a failure.
echo "Accepting Android SDK licenses ..."
yes | "$SDKMANAGER" --licenses > /dev/null 2>&1 || true

# ---- platform + build tools ----
if [[ $WITH_PLATFORM -eq 1 ]]; then
  echo "Installing platform-tools, platforms;android-${ANDROID_API}, build-tools;${BUILD_TOOLS} ..."
  "$SDKMANAGER" --install \
    "platform-tools" \
    "platforms;android-${ANDROID_API}" \
    "build-tools;${BUILD_TOOLS}" > /dev/null
else
  echo "Installing platform-tools ..."
  "$SDKMANAGER" --install "platform-tools" > /dev/null
fi

# The SDK is installed by root but used by coder; without this the whole tree is
# unreadable to the booth user.
chmod -R a+rX "$SDK_ROOT"

# ---- login-shell env ----
cat >/etc/profile.d/63-cb-android-sdk--profile.sh <<EOF
# Android SDK under /opt
export ANDROID_SDK_ROOT=${SDK_ROOT}
export ANDROID_HOME=${SDK_ROOT}
export PATH="\${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:\${ANDROID_SDK_ROOT}/platform-tools:\$PATH"
# build-tools carries aapt2/d8/apksigner/zipalign; the newest installed wins.
CB_ANDROID_BT="\$(ls -1d "\${ANDROID_SDK_ROOT}"/build-tools/* 2>/dev/null | sort -V | tail -n1)"
if [ -n "\$CB_ANDROID_BT" ]; then
  export PATH="\$CB_ANDROID_BT:\$PATH"
fi
unset CB_ANDROID_BT
EOF
chmod 0644 /etc/profile.d/63-cb-android-sdk--profile.sh

# ---- non-login wrappers ----
# Build scripts and IDE tasks run in non-login shells, which never source
# profile.d — without these, `adb` and `aapt2` are simply not found.
install -d "$BIN_DIR"
cat >"${BIN_DIR}/androidwrap" <<'EOF'
#!/bin/sh
: "${ANDROID_SDK_ROOT:=/opt/android-sdk}"
tool="$(basename "$0")"
for d in \
  "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" \
  "$ANDROID_SDK_ROOT/platform-tools" \
  "$(ls -1d "$ANDROID_SDK_ROOT"/build-tools/* 2>/dev/null | sort -V | tail -n1)"
do
  if [ -n "$d" ] && [ -x "$d/$tool" ]; then
    exec "$d/$tool" "$@"
  fi
done
echo "$tool: not found in the Android SDK at $ANDROID_SDK_ROOT" >&2
exit 127
EOF
chmod +x "${BIN_DIR}/androidwrap"

for t in sdkmanager avdmanager adb aapt2 d8 apksigner zipalign; do
  ln -sfn "${BIN_DIR}/androidwrap" "${BIN_DIR}/$t"
done

# ---- summary ----
# grep -m1 . takes the first NON-EMPTY line: sdkmanager pads its output with a
# blank line, which a plain `tail -n1` reports as an empty version. aapt2 prints
# its version on stderr, not stdout, so its stream has to be folded in.
echo "Android SDK installed at ${SDK_ROOT}."
echo -n "   sdkmanager: "; "${BIN_DIR}/sdkmanager" --version 2>/dev/null | grep -m1 . || echo "?"
if [[ $WITH_PLATFORM -eq 1 ]]; then
  echo -n "   aapt2:      "; "${BIN_DIR}/aapt2" version 2>&1 | grep -m1 . || echo "?"
  echo -n "   adb:        "; "${BIN_DIR}/adb" --version 2>/dev/null | grep -m1 . || echo "?"
fi

cat <<'EON'
Ready to use:
- Try: sdkmanager --list_installed
- Build an APK with aapt2 / d8 / apksigner (all on PATH)
- The emulator is a separate setup: android-emulator
EON
