#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>] [--with-lldb]

Examples:
  $0                      # install Swift 6.0.1 (default)
  $0 --version 6.0.2      # install a specific Swift release
  $0 --with-lldb          # also install lldb debugger (from apt)

Notes:
- Installs Swift to /opt/swift/swift-<ver> and links /opt/swift-stable
- Exposes swift/swiftc/swift-package/swift-build/swift-test via /usr/local/bin
- Supports Ubuntu 24.04 (noble), 22.04 (jammy), 20.04 (focal) on amd64/arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
SWIFT_DEFAULT_VER="6.0.1"
REQ_VER=""
WITH_LLDB=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    --with-lldb) WITH_LLDB=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

VERSION="${REQ_VER:-$SWIFT_DEFAULT_VER}"

# ---- arch & distro mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  S_ARCH="x86_64" ;;
  arm64)  S_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
case "$CODENAME" in
  noble|noble-updates|noble-security)  S_UBU="ubuntu24.04";;
  jammy|jammy-updates|jammy-security)  S_UBU="ubuntu22.04";;
  focal|focal-updates|focal-security)  S_UBU="ubuntu20.04";;
  *) echo "❌ Unsupported Ubuntu/Debian codename '$CODENAME'. Supported: focal (20.04), jammy (22.04), noble (24.04)."; exit 1;;
esac

# ---- dirs ----
INSTALL_PARENT=/opt/swift
TARGET_DIR="${INSTALL_PARENT}/swift-${VERSION}"
LINK_DIR=/opt/swift-stable
BIN_DIR=/usr/local/bin

# ---- base deps (runtime + common build deps Swift needs) ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl xz-utils tar git pkg-config \
  libc6 libstdc++6 libgcc-s1 \
  libcurl4 libxml2 libedit2 libsqlite3-0 zlib1g tzdata \
  libbsd0 libatomic1 libicu-dev \
  clang make
# optional debugger
if [ "$WITH_LLDB" -eq 1 ]; then
  apt-get install -y --no-install-recommends lldb
fi
rm -rf /var/lib/apt/lists/*

# ---- fetch toolchain tarball ----
# Official release URL pattern:
# https://download.swift.org/swift-<ver>-release/<ubuntuXX.XX>/swift-<ver>-RELEASE/swift-<ver>-RELEASE-<ubuntuXX.XX>.tar.gz
BASE="https://download.swift.org/swift-${VERSION}-release/${S_UBU}/swift-${VERSION}-RELEASE"
TARBALL="swift-${VERSION}-RELEASE-${S_UBU}.tar.gz"
URL="${BASE}/${TARBALL}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Swift ${VERSION} for ${S_UBU} (${S_ARCH}) ..."
# (The tarball is universal for the Ubuntu variant; arch-specific binaries are inside)
curl -fL "$URL" -o "$TMP/$TARBALL"

# ---- install ----
rm -rf "$TARGET_DIR"; mkdir -p "$TARGET_DIR"
echo "📦 Installing to ${TARGET_DIR} ..."
tar -xzf "$TMP/$TARBALL" -C "$TMP"
SRC_DIR="$(find "$TMP" -maxdepth 1 -type d -name "swift-${VERSION}-RELEASE-${S_UBU}" -print -quit)"
[[ -d "$SRC_DIR" ]] || { echo "❌ Extracted toolchain dir not found"; exit 1; }
# Move contents (usr/lib/swift, usr/bin, etc.) under our /opt target
mv "$SRC_DIR"/* "$TARGET_DIR"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login-shell env ----
cat >/etc/profile.d/99-swift--profile.sh <<'EOF'
# Swift under /opt
export SWIFT_HOME=/opt/swift-stable
export PATH="$SWIFT_HOME/usr/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-swift--profile.sh

# ---- non-login wrapper ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/swiftwrap" <<'EOF'
#!/bin/sh
: "${SWIFT_HOME:=/opt/swift-stable}"
export SWIFT_HOME PATH="$SWIFT_HOME/usr/bin:$PATH"
tool="$(basename "$0")"
exec "$SWIFT_HOME/usr/bin/$tool" "$@"
EOF
chmod +x "${BIN_DIR}/swiftwrap"

# common entrypoints
for t in swift swiftc swift-package swift-build swift-test; do
  ln -sfn "${BIN_DIR}/swiftwrap" "${BIN_DIR}/$t"
done

# ---- friendly summary ----
echo "✅ Swift ${VERSION} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   swift --version → "; "${BIN_DIR}/swift" --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: swift --version
- Works in login & non-login shells (wrapper primes PATH).
- Server/CLI only on Linux (no Apple SDKs).

Tips:
- Create a package:   swift package init --type executable
- Build & run:        swift build -c release && ./.build/release/<name>
- Popular frameworks: SwiftNIO, Vapor (via SPM)
EON
