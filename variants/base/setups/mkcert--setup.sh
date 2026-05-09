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
  $0                           # install latest mkcert
  $0 --version 1.4.4           # pin specific version

Notes:
- Installs mkcert to /usr/local/bin/mkcert (single static binary)
- Provisions a local CA in \$CAROOT and issues dev TLS certs
- See: https://github.com/FiloSottile/mkcert
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates libnss3-tools
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/FiloSottile/mkcert/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing mkcert v${VERSION} (${ARCH}) ..."
curl -fsSL "https://github.com/FiloSottile/mkcert/releases/download/v${VERSION}/mkcert-v${VERSION}-linux-${ARCH}" -o /usr/local/bin/mkcert
chmod +x /usr/local/bin/mkcert

echo "✅ mkcert installed."
echo -n "   mkcert → "; mkcert -version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Install local CA:   mkcert -install
- Issue cert:         mkcert example.local '*.example.local' localhost 127.0.0.1
- See: https://github.com/FiloSottile/mkcert
EON
