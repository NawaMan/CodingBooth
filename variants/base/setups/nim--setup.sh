#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

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
- x86_64: upstream's nim-<ver>-linux_x64.tar.xz from nim-lang.org
- arm64: nim-lang.org ships no linux_arm64 release, so it comes prebuilt (sha256-checked)
  from https://github.com/NawaMan/CodingBoothPrebuilt, laid out like upstream's x64 one;
  a version not prebuilt (yet) is built from nim-lang.org's source tarball (a few minutes)
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
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://nim-lang.org/channels/stable | tr -d '[:space:]')
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

fetch() {
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$1" -o "$2"
}

# Unpack nim-lang.org's <tarball> (holding nim-<ver>/) and move that folder to TARGET_DIR.
install_upstream_tree() {
  fetch "https://nim-lang.org/download/$1" "$TMP/$1"
  tar -xJf "$TMP/$1" -C "$TMP"
  local src="$TMP/nim-${VERSION}"
  [[ -d "$src" ]] || { echo "❌ Extracted Nim dir not found"; exit 1; }
  mv "$src" "$TARGET_DIR"
}

# Build from the release source tarball the way nim-lang builds its x64 release (minus
# the HTML docs), into TARGET_DIR. git: koch tools clones atlas.
build_from_source() {
  echo "ℹ️  Nim ${VERSION}: no prebuilt arm64 build; building from source..."
  apt-get update
  apt-get install -y --no-install-recommends build-essential git
  rm -rf /var/lib/apt/lists/*
  install_upstream_tree "nim-${VERSION}.tar.xz"
  (
    cd "$TARGET_DIR"
    export PATH="$TARGET_DIR/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/nimcache"
    make "-j$(nproc)" CC=gcc
    nim c koch
    ./koch boot -d:release
    ./koch tools -d:release
    rm -rf c_code build nimcache dist/atlas/.nimcache build.sh build*.bat makefile compiler/nim compiler/nim?
    find . -name '*.o' -delete
  )
}

rm -rf "$TARGET_DIR"
if [[ "$N_ARCH" == x64 ]]; then
  install_upstream_tree "nim-${VERSION}-linux_x64.tar.xz"
else
  SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
  if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
  fi
  source "${SETUP_LIBS_DIR}/prebuilt-source.sh"
  cb_prebuilt_install nim "$VERSION" native "$TARGET_DIR" || build_from_source
fi
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
