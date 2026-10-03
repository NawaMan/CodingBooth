#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest CMake
  $0 --version 3.31.6        # pin specific version

Notes:
- Installs CMake to /opt/cmake and symlinks to /usr/local/bin/
- Supports amd64 and arm64
- Downloads from GitHub (Kitware/CMake)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

PROFILE_FILE="/etc/profile.d/62-cb-cmake--profile.sh"

# ---- defaults / args ----
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64" ;;
  arm64) ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates jq
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  echo "🔍 Resolving latest CMake version ..."
  VERSION="$(curl --retry 3 --retry-delay 2 -s https://api.github.com/repos/Kitware/CMake/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
    echo "❌ Failed to resolve latest CMake version"; exit 1
  fi
  echo "   Latest version: ${VERSION}"
else
  if [[ ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like X.Y.Z (e.g., 3.31.6)"; exit 2
  fi
  VERSION="$REQ_VER"
fi

# ---- download and install ----
TARBALL_URL="https://github.com/Kitware/CMake/releases/download/v${VERSION}/cmake-${VERSION}-linux-${ARCH}.tar.gz"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading CMake ${VERSION} (${ARCH}) ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$TARBALL_URL" -o "$TMP/cmake.tar.gz"

echo "📦 Extracting to /opt/cmake ..."
rm -rf /opt/cmake
mkdir -p /opt/cmake
tar -xzf "$TMP/cmake.tar.gz" -C /opt/cmake --strip-components=1

# Sanity check
if [[ ! -x /opt/cmake/bin/cmake ]]; then
  echo "❌ Installation appears incomplete: /opt/cmake/bin/cmake not found" >&2
  exit 1
fi

# ---- symlinks to /usr/local/bin ----
echo "🛠  Creating symlinks in /usr/local/bin ..."
install -d /usr/local/bin
for bin in cmake ctest cpack; do
  ln -sfn "/opt/cmake/bin/${bin}" "/usr/local/bin/${bin}"
done

# ---- profile script ----
cat >"${PROFILE_FILE}" <<'EOF'
# ---- CMake environment (safe to source multiple times) ----
export CMAKE_HOME=/opt/cmake
case ":$PATH:" in
  *":$CMAKE_HOME/bin:"*) : ;;
  *) export PATH="$CMAKE_HOME/bin:$PATH" ;;
esac
# ---- end CMake defaults ----
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- friendly summary ----
INSTALLED_VER="$(cmake --version | head -1)"
echo "✅ CMake installed: ${INSTALLED_VER}"
echo "   Binary:   /opt/cmake/bin/cmake"
echo "   Symlinks: /usr/local/bin/{cmake,ctest,cpack}"
echo "   Profile:  ${PROFILE_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: cmake --version
- Common commands:
    cmake -S . -B build      # configure a project
    cmake --build build       # build the project
    ctest --test-dir build    # run tests
    cpack --config build      # create packages
EON
