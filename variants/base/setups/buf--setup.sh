#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# buf--setup.sh — Install the Buf CLI from GitHub releases
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                           # install latest buf
  $0 --version 1.72.0          # pin specific version

Notes:
- Installs buf to /usr/local/bin/buf from bufbuild/buf GitHub releases
- Does not install protoc or language plugins
- See: https://buf.build/docs/cli/installation/
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

# Buf release assets use uname-style names: Linux-x86_64, Linux-aarch64
OS="$(uname -s)"
MACHINE="$(uname -m)"
case "${OS}-${MACHINE}" in
  Linux-x86_64|Linux-amd64) ASSET_OS="Linux"; ASSET_ARCH="x86_64" ;;
  Linux-aarch64|Linux-arm64) ASSET_OS="Linux"; ASSET_ARCH="aarch64" ;;
  *)
    echo "❌ Unsupported platform: ${OS} ${MACHINE} (need Linux x86_64 or aarch64)" >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

# Known-good pin when the GitHub API is rate-limited or returns minified JSON
# that older parsers mis-read (see mkcert--setup.sh for the "eyes" failure mode).
FALLBACK_VERSION="1.50.0"

if [[ "$REQ_VER" == "latest" ]]; then
  # Match the tag_name *key* only — never sed the whole JSON line (minified
  # payloads put everything on one line; greedy sed grabs the last quote).
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/bufbuild/buf/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "⚠️  Could not resolve latest buf from GitHub (got '${VERSION:-empty}'); falling back to v${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
  fi
else
  VERSION="${REQ_VER#v}"
fi

if [[ -z "${VERSION}" ]] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Could not resolve buf version (got '${VERSION:-empty}')" >&2
  exit 1
fi

ASSET="buf-${ASSET_OS}-${ASSET_ARCH}"
URL="https://github.com/bufbuild/buf/releases/download/v${VERSION}/${ASSET}"

echo "⬇️  Installing buf v${VERSION} (${ASSET_OS}-${ASSET_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$URL" -o "$TMP/buf"
install -m 755 "$TMP/buf" /usr/local/bin/buf

echo "✅ buf installed."
echo -n "   buf → "; buf --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Version:           buf --version
- Lint:              buf lint
- Generate:          buf generate
- Breaking change:   buf breaking --against '.git#branch=main'
- protoc / plugins:  select the protobuf template (and language extensions) separately
- Docs:              https://buf.build/docs/cli/installation/
EON
