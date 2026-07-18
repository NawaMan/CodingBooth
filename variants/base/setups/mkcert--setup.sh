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

# Last published mkcert release. Also the fallback when the GitHub API is
# unreachable or rate-limited (unauthenticated api.github.com allows only
# 60 req/h per IP, which a full build+test run can exhaust).
FALLBACK_VERSION="1.4.4"

if [[ "$REQ_VER" == "latest" ]]; then
  # `|| true` so a rate-limited/failed API call yields an empty string and we
  # fall back, instead of aborting the whole setup under `set -e`/pipefail.
  # --retry-all-errors so a 429 (rate limit) / 5xx is retried too; plain --retry
  # only covers connection-level errors, letting an HTTP error through on the
  # first try.
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/FiloSottile/mkcert/releases/latest 2>/dev/null \
            | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    echo "⚠️  Could not resolve latest mkcert from GitHub (rate limit or network); falling back to v${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid mkcert version resolved: '${VERSION}'" >&2
  exit 1
fi

# Download the binary, retrying HTTP errors (429/5xx) as well as connection
# errors. If the resolved version's asset can't be fetched, fall back to the
# known-good version before giving up — a full build+test run can trip GitHub's
# rate limit for minutes at a time.
download_mkcert() {
  local ver="$1"
  local url="https://github.com/FiloSottile/mkcert/releases/download/v${ver}/mkcert-v${ver}-linux-${ARCH}"
  echo "⬇️  Installing mkcert v${ver} (${ARCH}) ..."
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "$url" -o /usr/local/bin/mkcert
}

if ! download_mkcert "$VERSION"; then
  if [[ "$VERSION" != "$FALLBACK_VERSION" ]]; then
    echo "⚠️  Download of v${VERSION} failed; retrying with fallback v${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
    download_mkcert "$VERSION" || { echo "❌ Failed to download mkcert (v${VERSION})" >&2; exit 1; }
  else
    echo "❌ Failed to download mkcert (v${VERSION})" >&2
    exit 1
  fi
fi
chmod +x /usr/local/bin/mkcert

# Verify the binary actually runs — a truncated or HTML error-page download
# would otherwise pass silently and fail only much later.
if ! /usr/local/bin/mkcert -version >/dev/null 2>&1; then
  echo "❌ mkcert downloaded but is not runnable (bad download?)" >&2
  exit 1
fi

echo "✅ mkcert installed."
echo -n "   mkcert → "; mkcert -version

cat <<'EON'
ℹ️ Ready to use:
- Install local CA:   mkcert -install
- Issue cert:         mkcert example.local '*.example.local' localhost 127.0.0.1
- See: https://github.com/FiloSottile/mkcert
EON
