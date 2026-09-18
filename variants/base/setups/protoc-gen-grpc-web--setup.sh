#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION]

Arguments:
  VERSION  protoc-gen-grpc-web version to install (default: 2.1.1)

Examples:
  $0            # install the default pinned version
  $0 2.0.1      # pin a different version

Notes:
- Installs protoc-gen-grpc-web to /usr/local/bin, a standalone protoc
  plugin for generating gRPC-Web client code for browsers.
- Downloaded as a prebuilt native executable from grpc/grpc-web's
  GitHub releases; no Node.js is used to run it.
- See: https://github.com/grpc/grpc-web
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

VERSION="${1:-2.1.1}"

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ASSET_ARCH="x86_64" ;;
  arm64) ASSET_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

ASSET="protoc-gen-grpc-web-${VERSION}-linux-${ASSET_ARCH}"
BASE_URL="https://github.com/grpc/grpc-web/releases/download/${VERSION}"

echo "⬇️  Installing protoc-gen-grpc-web v${VERSION} (linux-${ASSET_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ASSET}" -o "$TMP/protoc-gen-grpc-web"

# Verify SHA-256 if available.
if curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ASSET}.sha256" -o "$TMP/${ASSET}.sha256" 2>/dev/null; then
  echo "Verifying checksum..."
  (cd "$TMP" && sha256sum -c "${ASSET}.sha256" --status) || {
    echo "❌ SHA-256 mismatch for protoc-gen-grpc-web ${VERSION}" >&2
    exit 1
  }
else
  echo "⚠️  No SHA-256 file found; skipping checksum verification."
fi

install -m 755 "$TMP/protoc-gen-grpc-web" /usr/local/bin/protoc-gen-grpc-web

echo "✅ protoc-gen-grpc-web installed."
echo "   Version:  ${VERSION}"
echo "   Location: /usr/local/bin/protoc-gen-grpc-web"

cat <<'EON'
ℹ️ Ready to use:
- Generate gRPC-Web client code:
    protoc --js_out=import_style=commonjs:. \
           --grpc-web_out=import_style=commonjs,mode=grpcwebtext:. \
           -I. file.proto
- Needs the `protoc-gen-js` plugin too for --js_out (separate from this).
- Source / releases: https://github.com/grpc/grpc-web/releases
EON
