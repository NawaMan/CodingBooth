#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs nodejs at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
NODE_MAJOR=20

# --- Parse args ---
if [[ $# -ge 1 && ! "$1" =~ ^-- ]]; then
  NODE_MAJOR="$1"
  shift
fi

# Determine latest version for the major
NODE_VERSION=$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/" | grep -oP 'node-v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -z "$NODE_VERSION" ]]; then
  echo "❌ Could not determine latest Node.js v${NODE_MAJOR} version"
  exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  NODE_ARCH="x64" ;;
  aarch64) NODE_ARCH="arm64" ;;
  armv7l)  NODE_ARCH="armv7l" ;;
  *)       echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"
INSTALL_DIR="/usr/local"

echo "• Installing Node.js v${NODE_VERSION} (${NODE_ARCH}) to ${INSTALL_DIR}"

# Download and extract
cd /tmp
curl -fsSL -o "$NODE_TARBALL" "$NODE_URL"
tar -xJf "$NODE_TARBALL"
cp -r "node-v${NODE_VERSION}-linux-${NODE_ARCH}"/{bin,lib,include,share} "$INSTALL_DIR"/
rm -rf "$NODE_TARBALL" "node-v${NODE_VERSION}-linux-${NODE_ARCH}"

# Verify installation
echo "• Verifying installation..."
node --version
npm --version

echo "✅ Node.js v${NODE_VERSION} installed to ${INSTALL_DIR}"
