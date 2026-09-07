#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# appwrite-cli--setup.sh — Install the Appwrite CLI from GitHub releases
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                           # install latest Appwrite CLI
  $0 --version 27.3.0          # pin a specific CLI version

Notes:
- Installs the official Appwrite CLI (appwrite) from appwrite/sdk-for-cli
- Talks to Appwrite Cloud or a self-hosted instance (see setup appwrite-server)
- Supports amd64 and arm64
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
REQ_VER="${REQ_VER#v}"

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ASSET_ARCH="x64" ;;
  arm64) ASSET_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)" >&2; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

# Known-good pin when the GitHub API is rate-limited.
FALLBACK_VERSION="27.3.0"

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/appwrite/sdk-for-cli/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*([.-][A-Za-z0-9]+)*$ ]]; then
    echo "⚠️  Could not resolve latest Appwrite CLI from GitHub (got '${VERSION:-empty}'); falling back to ${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
  fi
else
  VERSION="$REQ_VER"
fi

if [[ -z "${VERSION}" ]]; then
  echo "❌ Could not resolve Appwrite CLI version (got '${VERSION:-empty}')" >&2
  exit 1
fi

ASSET="appwrite-cli-linux-${ASSET_ARCH}"
URL="https://github.com/appwrite/sdk-for-cli/releases/download/${VERSION}/${ASSET}"

echo "⬇️  Installing Appwrite CLI ${VERSION} (${ASSET_ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "${TMP_DIR}/appwrite"
install -m 755 "${TMP_DIR}/appwrite" /usr/local/bin/appwrite
rm -rf "${TMP_DIR}"

echo "✅ Appwrite CLI installed."
echo -n "   appwrite → "; appwrite -v 2>/dev/null || appwrite version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: appwrite -v
- Login (Cloud): appwrite login
- Point at a local server: appwrite client --endpoint http://localhost:8080/v1 --self-signed true

Notes:
- Host credentials live in ~/.appwrite — select appwrite-cli+credential to seed them.
- Pair with appwrite-server to run a self-hosted instance inside the booth.
- See: https://appwrite.io/docs/tooling/command-line/installation
EON
