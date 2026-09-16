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
  $0                    # install latest PostgREST
  $0 --version 12.2.8   # pin a release

Notes:
- Installs the static Linux binary from PostgREST/postgrest GitHub releases
  (not the postgrest/postgrest Docker image).
- Requires PostgreSQL already installed (postgresql--setup.sh); does not start
  the server itself — select the postgrest autostart extension for that.
- See: https://docs.postgrest.org/en/stable/explanations/install.html
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
  amd64) ARCH="x86-64" ;;
  arm64) ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)" >&2; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar xz-utils
  rm -rf /var/lib/apt/lists/*
fi

# Known-good pin for when the GitHub API is rate-limited or returns minified JSON.
FALLBACK_VERSION="16.3"

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
              https://api.github.com/repos/PostgREST/postgrest/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "⚠️  Could not resolve latest PostgREST from GitHub (got '${VERSION:-empty}'); falling back to v${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
  fi
else
  VERSION="$REQ_VER"
fi

if [[ -z "${VERSION}" ]] || ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "❌ Could not resolve PostgREST version (got '${VERSION:-empty}')" >&2
  exit 1
fi

ASSET="postgrest-v${VERSION}-linux-static-${ARCH}.tar.xz"
URL="https://github.com/PostgREST/postgrest/releases/download/v${VERSION}/${ASSET}"

echo "⬇️  Installing PostgREST v${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP_DIR/postgrest.tar.xz"
tar -xJf "$TMP_DIR/postgrest.tar.xz" -C "$TMP_DIR"

POSTGREST_BIN="$(find "$TMP_DIR" -type f -name postgrest | head -1)"
if [[ -z "$POSTGREST_BIN" ]]; then
  echo "❌ postgrest binary not found in downloaded archive" >&2
  exit 1
fi

install -m 755 "$POSTGREST_BIN" /usr/local/bin/postgrest

echo ""
echo "✅ PostgREST v${VERSION} installed at /usr/local/bin/postgrest."
echo "   Not started; select the postgrest autostart extension to run it on boot."
