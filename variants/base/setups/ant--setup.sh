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

# This script will always be installed by root.
HOME=/root

PROFILE_FILE="/etc/profile.d/62-cb-ant--profile.sh"

ANT_VERSION=${1:-1.10.18}

# Optional override (e.g., corporate mirror): export ANT_MIRROR_BASE="https://my-mirror.example.com/ant"
BASE="${ANT_MIRROR_BASE:-https://archive.apache.org/dist/ant/binaries}"

INSTALL_PARENT=/opt/ant
TARGET_DIR="${INSTALL_PARENT}/apache-ant-${ANT_VERSION}"
LINK_DIR=/opt/ant-stable

tarball="apache-ant-${ANT_VERSION}-bin.tar.gz"
download_url="${BASE}/${tarball}"
sha_url="${download_url}.sha512"

echo "Locating Ant ${ANT_VERSION}..."
# HEAD check (fast fail if unreachable)
curl --retry 3 --retry-delay 2 -fsIL "$download_url" >/dev/null

# --- Download archive ---
echo "Downloading: $download_url"
curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 10 \
     "$download_url" -o /tmp/ant.tar.gz

# --- Verify SHA-512 if available. Apache publishes a bare hex digest here
# (no trailing filename, unlike Gradle's "hash  filename" format), so just
# compare the raw hex. ---
if curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 10 \
        "$sha_url" -o /tmp/ant.tar.gz.sha512 2>/dev/null; then
  echo "Verifying checksum..."
  expected="$(tr -d '[:space:]' < /tmp/ant.tar.gz.sha512)"
  actual="$(sha512sum /tmp/ant.tar.gz | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    echo "❌ SHA-512 mismatch for Ant ${ANT_VERSION}" >&2
    exit 1
  fi
else
  echo "⚠️  No SHA-512 file found at ${sha_url}; skipping checksum verification."
fi
rm -f /tmp/ant.tar.gz.sha512 || true

# --- Install into /opt/ant/apache-ant-<version> ---
rm    -rf  "$TARGET_DIR"
mkdir -p   "$INSTALL_PARENT"
tar   -xzf /tmp/ant.tar.gz -C "$INSTALL_PARENT"
rm    -f   /tmp/ant.tar.gz

# Sanity check
if [ ! -x "${TARGET_DIR}/bin/ant" ]; then
  echo "❌ Installation appears incomplete: ${TARGET_DIR}/bin/ant not found" >&2
  exit 1
fi

# --- Stable symlink directory for Ant ---
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- Make ant available even in non-login shells ---
install -d /usr/local/bin
ln -sfn "$LINK_DIR/bin/ant" /usr/local/bin/ant

# --- environment for login shells ---
cat >"${PROFILE_FILE}" <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export ANT_HOME=/opt/ant-stable
export PATH="$ANT_HOME/bin:$PATH"
# ---- end defaults ----
EOF
chmod 0644 "${PROFILE_FILE}"

echo "✅ Ant ${ANT_VERSION} installed to ${TARGET_DIR} and linked at ${LINK_DIR}."
echo "   Try: ant -version"
