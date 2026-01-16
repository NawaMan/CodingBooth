#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs deno at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
DENO_VERSION="latest"

# --- Parse args ---
if [[ $# -ge 1 && ! "$1" =~ ^-- ]]; then
  DENO_VERSION="$1"
  shift
fi

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  DENO_ARCH="x86_64" ;;
  aarch64) DENO_ARCH="aarch64" ;;
  *)       echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

INSTALL_DIR="/usr/local/bin"

# Determine download URL
if [[ "$DENO_VERSION" == "latest" ]]; then
  DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-${DENO_ARCH}-unknown-linux-gnu.zip"
  echo "• Installing Deno (latest) for ${DENO_ARCH} to ${INSTALL_DIR}"
else
  DENO_URL="https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-${DENO_ARCH}-unknown-linux-gnu.zip"
  echo "• Installing Deno v${DENO_VERSION} (${DENO_ARCH}) to ${INSTALL_DIR}"
fi

# Download and extract
cd /tmp
curl -fsSL -o deno.zip "$DENO_URL"
unzip -o deno.zip
cp deno "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/deno"
rm -rf deno.zip deno

# Verify installation
echo "• Verifying installation..."
deno --version

echo "✅ Deno installed to ${INSTALL_DIR}"
