#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs bun at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root


# --- Defaults ---
BUN_VERSION="latest"

# --- Parse args ---
if [[ $# -ge 1 && ! "$1" =~ ^-- ]]; then
  BUN_VERSION="$1"
  shift
fi

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BUN_ARCH="x64" ;;
  aarch64) BUN_ARCH="aarch64" ;;
  *)       echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

INSTALL_DIR="/usr/local/bin"

# Determine download URL
if [[ "$BUN_VERSION" == "latest" ]]; then
  BUN_URL="https://github.com/oven-sh/bun/releases/latest/download/bun-linux-${BUN_ARCH}.zip"
  echo "• Installing Bun (latest) for ${BUN_ARCH} to ${INSTALL_DIR}"
else
  BUN_URL="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${BUN_ARCH}.zip"
  echo "• Installing Bun v${BUN_VERSION} (${BUN_ARCH}) to ${INSTALL_DIR}"
fi

# Download and extract
cd /tmp
curl -fsSL -o bun.zip "$BUN_URL"
unzip -o bun.zip
cp "bun-linux-${BUN_ARCH}/bun" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/bun"
rm -rf bun.zip "bun-linux-${BUN_ARCH}"

# Verify installation
echo "• Verifying installation..."
bun --version

echo "✅ Bun installed to ${INSTALL_DIR}"
