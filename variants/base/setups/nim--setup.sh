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
  $0                           # install latest Nim
  $0 --version 2.0.10          # pin specific version

Notes:
- Installs Nim to /opt/nim-<ver> and links /opt/nim-stable
- Exposes nim/nimble/nimsuggest/nimgrep via /usr/local/bin
- Upstream tarballs from nim-lang.org: nim-<ver>-linux_<x64|arm64>.tar.xz
- See: https://nim-lang.org
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
  amd64) N_ARCH="x64" ;;
  arm64) N_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates xz-utils tar gcc make
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  # Nim doesn't publish GitHub Releases; nim-lang.org/channels/stable is the
  # canonical pointer that choosenim uses internally. Returns just "X.Y.Z\n".
  VERSION=$(curl -fsSL https://nim-lang.org/channels/stable | tr -d '[:space:]')
  VERSION="${VERSION#v}"
else
  VERSION="${REQ_VER#v}"
fi

INSTALL_PARENT=/opt
TARGET_DIR="${INSTALL_PARENT}/nim-${VERSION}"
LINK_DIR="${INSTALL_PARENT}/nim-stable"
BIN_DIR=/usr/local/bin

echo "⬇️  Installing Nim ${VERSION} (${N_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TARBALL="nim-${VERSION}-linux_${N_ARCH}.tar.xz"
curl -fsSL "https://nim-lang.org/download/${TARBALL}" -o "$TMP/$TARBALL"
tar -xJf "$TMP/$TARBALL" -C "$TMP"

SRC_DIR="$(find "$TMP" -maxdepth 1 -type d -name "nim-${VERSION}" -print -quit)"
[[ -d "$SRC_DIR" ]] || { echo "❌ Extracted Nim dir not found"; exit 1; }

rm -rf "$TARGET_DIR"
mv "$SRC_DIR" "$TARGET_DIR"
ln -sfn "$TARGET_DIR" "$LINK_DIR"

cat >/etc/profile.d/99-nim--profile.sh <<'EOF'
# Nim toolchain
export NIM_HOME=/opt/nim-stable
export PATH="$NIM_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-nim--profile.sh

install -d "$BIN_DIR"
for t in nim nimble nimsuggest nimgrep; do
  if [[ -x "${LINK_DIR}/bin/$t" ]]; then
    ln -sfn "${LINK_DIR}/bin/$t" "${BIN_DIR}/$t"
  fi
done

echo "✅ Nim ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   nim → "; "${BIN_DIR}/nim" --version 2>/dev/null | head -1 || true

cat <<'EON'
ℹ️ Ready to use:
- Compile & run:  nim c -r hello.nim
- New project:    nimble init myapp
- See: https://nim-lang.org
EON
