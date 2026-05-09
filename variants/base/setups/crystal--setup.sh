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
  $0                           # install latest Crystal
  $0 --version 1.13.3          # pin specific version

Notes:
- Installs Crystal to /opt/crystal-<ver> and links /opt/crystal-stable
- Exposes crystal/shards via /usr/local/bin
- Upstream tarballs are named: crystal-<ver>-1-linux-<x86_64|aarch64>.tar.gz
- See: https://crystal-lang.org
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
  amd64) C_ARCH="x86_64" ;;
  arm64) C_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates tar gzip \
  libevent-dev libgmp-dev libpcre3-dev libssl-dev libxml2-dev libyaml-dev \
  zlib1g-dev pkg-config gcc make
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/crystal-lang/crystal/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

INSTALL_PARENT=/opt
TARGET_DIR="${INSTALL_PARENT}/crystal-${VERSION}"
LINK_DIR="${INSTALL_PARENT}/crystal-stable"
BIN_DIR=/usr/local/bin

echo "⬇️  Installing Crystal ${VERSION} (${C_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TARBALL="crystal-${VERSION}-1-linux-${C_ARCH}.tar.gz"
curl -fsSL "https://github.com/crystal-lang/crystal/releases/download/${VERSION}/${TARBALL}" -o "$TMP/$TARBALL"
tar -xzf "$TMP/$TARBALL" -C "$TMP"

SRC_DIR="$(find "$TMP" -maxdepth 1 -type d -name "crystal-${VERSION}-1" -print -quit)"
[[ -d "$SRC_DIR" ]] || { echo "❌ Extracted Crystal dir not found"; exit 1; }

rm -rf "$TARGET_DIR"
mv "$SRC_DIR" "$TARGET_DIR"
ln -sfn "$TARGET_DIR" "$LINK_DIR"

cat >/etc/profile.d/99-crystal--profile.sh <<'EOF'
# Crystal toolchain
export CRYSTAL_HOME=/opt/crystal-stable
export PATH="$CRYSTAL_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-crystal--profile.sh

install -d "$BIN_DIR"
ln -sfn "${LINK_DIR}/bin/crystal" "${BIN_DIR}/crystal"
ln -sfn "${LINK_DIR}/bin/shards"  "${BIN_DIR}/shards"

echo "✅ Crystal ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   crystal → "; "${BIN_DIR}/crystal" --version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Compile & run:  crystal run hello.cr
- New project:    crystal init app myapp && cd myapp && shards install
- See: https://crystal-lang.org
EON
