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
  $0

Examples:
  $0                          # install the current stable ngrok agent (v3)

Notes:
- Installs the ngrok agent to /usr/local/bin/ngrok
- Supports amd64 and arm64
- Always the current stable v3 build: ngrok publishes no versioned download
  URLs, so there is no version pin. Inside the booth, \`ngrok update\` moves on.
- ngrok needs an account: put the authtoken in NGROK_AUTHTOKEN (the ngrok+share
  extension passes it from the host) or run \`ngrok config add-authtoken <token>\`.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar
  rm -rf /var/lib/apt/lists/*
fi

# ---- install ----
echo "⬇️  Installing the ngrok agent (v3 stable, ${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${ARCH}.tgz" \
  -o "${TMP_DIR}/ngrok.tgz"
tar -xzf "${TMP_DIR}/ngrok.tgz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/ngrok" /usr/local/bin/ngrok
rm -rf "${TMP_DIR}"

# ---- friendly summary ----
echo "✅ ngrok installed."
echo -n "   ngrok → "; ngrok version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Log in once (or set NGROK_AUTHTOKEN):  ngrok config add-authtoken <token>
- Share a local web server:              ngrok http 8080

Notes:
- The authtoken is on https://dashboard.ngrok.com/get-started/your-authtoken
- See: https://ngrok.com/docs/agent/
EON
