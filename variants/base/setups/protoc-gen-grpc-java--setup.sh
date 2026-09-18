#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION]

Arguments:
  VERSION  protoc-gen-grpc-java version to install (default: 1.84.0)

Examples:
  $0            # install the default pinned version
  $0 1.66.0     # pin a different version

Notes:
- Installs protoc-gen-grpc-java to /usr/local/bin, a standalone protoc
  plugin for generating gRPC service code from .proto files -- plain
  Java message codegen (protoc --java_out) needs no plugin at all.
- Downloaded as a prebuilt native executable from Maven Central
  (io.grpc:protoc-gen-grpc-java); no JVM is used to run it.
- See: https://github.com/grpc/grpc-java/tree/master/compiler
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

VERSION="${1:-1.84.0}"

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ASSET_ARCH="x86_64" ;;
  arm64) ASSET_ARCH="aarch_64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

ASSET="protoc-gen-grpc-java-${VERSION}-linux-${ASSET_ARCH}.exe"
URL="https://repo1.maven.org/maven2/io/grpc/protoc-gen-grpc-java/${VERSION}/${ASSET}"

echo "⬇️  Installing protoc-gen-grpc-java v${VERSION} (linux-${ASSET_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/protoc-gen-grpc-java"
install -m 755 "$TMP/protoc-gen-grpc-java" /usr/local/bin/protoc-gen-grpc-java

echo "✅ protoc-gen-grpc-java installed."
echo "   Version:  ${VERSION}"
echo "   Location: /usr/local/bin/protoc-gen-grpc-java"

cat <<'EON'
ℹ️ Ready to use:
- Generate gRPC service code:
    protoc --java_out=. --grpc-java_out=. -I. file.proto
- Plain message codegen (--java_out) needs no plugin -- it's built
  into protoc itself.
- Source / version list: https://repo1.maven.org/maven2/io/grpc/protoc-gen-grpc-java/
EON
