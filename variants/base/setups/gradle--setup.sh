#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

PROFILE_FILE="/etc/profile.d/62-ws-gradle--profile.sh"

GRADLE_VERSION=${1:-9.1.0}

# Optional override (e.g., corporate mirror): export GRADLE_MIRROR_BASE="https://my-mirror.example.com/gradle"
BASE="${GRADLE_MIRROR_BASE:-https://services.gradle.org}/distributions"

INSTALL_PARENT=/opt/gradle
TARGET_DIR="${INSTALL_PARENT}/gradle-${GRADLE_VERSION}"
LINK_DIR=/opt/gradle-stable

zipfile="gradle-${GRADLE_VERSION}-bin.zip"
download_url="${BASE}/${zipfile}"
sha_url="${download_url}.sha256"

echo "Locating Gradle ${GRADLE_VERSION}..."
# HEAD check (fast fail if unreachable)
curl -fsIL "$download_url" >/dev/null

# --- Download archive ---
echo "Downloading: $download_url"
curl -fsSL "$download_url" -o /tmp/gradle.zip

# --- Verify SHA-256 if available ---
if curl -fsSL "$sha_url" -o /tmp/gradle.zip.sha256 2>/dev/null; then
  echo "Verifying checksum..."
  expected="$(cut -d' ' -f1 /tmp/gradle.zip.sha256)"
  actual="$(sha256sum /tmp/gradle.zip | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    echo "❌ SHA-256 mismatch for Gradle ${GRADLE_VERSION}" >&2
    exit 1
  fi
else
  echo "⚠️  No SHA-256 file found at ${sha_url}; skipping checksum verification."
fi
rm -f /tmp/gradle.zip.sha256 || true

# --- Install into /opt/gradle/gradle-<version> ---
rm    -rf  "$TARGET_DIR"
mkdir -p   "$TARGET_DIR"
unzip -q   /tmp/gradle.zip -d "$TARGET_DIR"
rm    -f   /tmp/gradle.zip

# Gradle zips contain a top-level directory (gradle-<version>)—move contents up if needed
if [ -d "${TARGET_DIR}/gradle-${GRADLE_VERSION}" ]; then
  shopt -s dotglob
  mv "${TARGET_DIR}/gradle-${GRADLE_VERSION}/"* "${TARGET_DIR}/"
  rmdir "${TARGET_DIR}/gradle-${GRADLE_VERSION}"
  shopt -u dotglob
fi

# Sanity check
if [ ! -x "${TARGET_DIR}/bin/gradle" ]; then
  echo "❌ Installation appears incomplete: ${TARGET_DIR}/bin/gradle not found" >&2
  exit 1
fi

# --- Stable symlink directory for Gradle ---
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- Make gradle available even in non-login shells ---
install -d /usr/local/bin
ln -sfn "$LINK_DIR/bin/gradle" /usr/local/bin/gradle

# --- environment for login shells ---
cat >"${PROFILE_FILE}" <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export GRADLE_HOME=/opt/gradle-stable
export PATH="$GRADLE_HOME/bin:$PATH"
# ---- end defaults ----
EOF
chmod 0644 "${PROFILE_FILE}"

echo "✅ Gradle ${GRADLE_VERSION} installed to ${TARGET_DIR} and linked at ${LINK_DIR}."
echo "   Try: gradle --version"
