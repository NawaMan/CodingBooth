#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <YYYY.M.N>|latest]

Examples:
  $0                          # install the latest cloudflared release
  $0 --version 2026.11.0      # pin a specific release

Notes:
- Installs cloudflared (Cloudflare Tunnel client) to /usr/local/bin/cloudflared
- Supports amd64 and arm64
- Quick tunnels (cloudflared tunnel --url ...) need no Cloudflare account
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
CLOUDFLARED_DEFAULT_VER="2026.11.0"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/cloudflare/cloudflared/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
            | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # The GitHub API is rate-limited; degrade to the pinned default instead of
    # failing the build (same as lazygit--setup.sh).
    echo "⚠️  Could not resolve the latest cloudflared release; using ${CLOUDFLARED_DEFAULT_VER}."
    VERSION="$CLOUDFLARED_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install ----
echo "⬇️  Installing cloudflared ${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/cloudflare/cloudflared/releases/download/${VERSION}/cloudflared-linux-${ARCH}" \
  -o "${TMP_DIR}/cloudflared"
install -m 755 "${TMP_DIR}/cloudflared" /usr/local/bin/cloudflared
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ cloudflared installed."
echo -n "   cloudflared → "; cloudflared --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Share a local web server (no account needed):  cloudflared tunnel --url http://localhost:8080
- Named tunnels on your own domain:              cloudflared tunnel login

Notes:
- A quick tunnel gives a random https://<words>.trycloudflare.com URL that
  anyone can open while the command runs.
- See: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
EON
