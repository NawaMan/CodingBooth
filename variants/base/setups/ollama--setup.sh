#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest Ollama
  $0 --version 0.6.2         # pin specific version

Notes:
- Downloads Ollama binary from GitHub releases
- Installs to /usr/local/bin/ollama
- Supports amd64 and arm64
- Ollama must be started manually with 'ollama serve' before use
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates zstd
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/ollama/ollama/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
else
  VERSION="$REQ_VER"
fi

# ---- download and install ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TARBALL_URL="https://github.com/ollama/ollama/releases/download/v${VERSION}/ollama-linux-${ARCH}.tar.zst"
echo "⬇️  Installing Ollama v${VERSION} (${ARCH}) ..."
curl -fsSL "$TARBALL_URL" -o "$TMP/ollama.tar.zst"
tar --zstd -xf "$TMP/ollama.tar.zst" -C "$TMP"

# Install the ollama binary (it's in bin/ inside the tarball)
install -m 755 "$TMP/bin/ollama" /usr/local/bin/ollama

# ---- startup script: create ~/.ollama for model storage ----
STARTUP_FILE="/usr/share/startup.d/70-cb-ollama--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Ollama startup script
# Creates ~/.ollama directory for model storage

mkdir -p "$HOME/.ollama"
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- friendly summary ----
echo "✅ Ollama installed."
echo -n "   ollama → "; ollama --version 2>/dev/null || true
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Start the server: ollama serve &
- Pull a model:     ollama pull llama3
- Chat:             ollama run llama3

Notes:
- Ollama must be started with 'ollama serve' before pulling or running models.
- Models are stored in ~/.ollama (created on container start).
- GPU passthrough requires appropriate Docker flags (e.g., --gpus all).
- See: https://ollama.com/
EON
