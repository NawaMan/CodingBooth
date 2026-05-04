#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <N>]

Examples:
  $0                  # default GCC 13
  $0 --version 12     # install GCC 12 + G++ 12

Notes:
- Installs into /opt/gcc/gcc-<N> and links /opt/gcc-stable
- Adds wrappers in /usr/local/bin so gcc/g++ work in non-login shells
- Registers with update-alternatives (priority 50, lower than Clang's 100)
- Sets CC=gcc, CXX=g++ ONLY if Clang did not already set them
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
GCC_DEFAULT=13
REQ_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

GCC_VER="${REQ_VER:-$GCC_DEFAULT}"

LEVEL=64                          # See README.md - Profile Ordering

PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-gcc--profile.sh"

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates software-properties-common
rm -rf /var/lib/apt/lists/*

# ---- check availability ----
PKGS="gcc-${GCC_VER} g++-${GCC_VER}"
apt-get update
if ! apt-cache show $PKGS >/dev/null 2>&1; then
  echo "❌ GCC $GCC_VER not available in this distribution." >&2
  exit 1
fi

echo "📦 Installing GCC ${GCC_VER} ..."
apt-get install -y --no-install-recommends $PKGS
rm -rf /var/lib/apt/lists/*

# ---- dirs ----
INSTALL_PARENT=/opt/gcc
TARGET_DIR="${INSTALL_PARENT}/gcc-${GCC_VER}"
LINK_DIR=/opt/gcc-stable
BIN_DIR=/usr/local/bin

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR/bin"

# Symlink installed binaries into /opt/gcc/gcc-<ver>/bin
ln -sfn "$(command -v gcc-${GCC_VER})" "$TARGET_DIR/bin/gcc"
ln -sfn "$(command -v g++-${GCC_VER})" "$TARGET_DIR/bin/g++"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- login shell env ----
cat >"${PROFILE_FILE}" <<'EOF'
# Profile: GCC defaults
export GCC_HOME=/opt/gcc-stable
case ":$PATH:" in
  *":$GCC_HOME/bin:"*) ;;
  *) export PATH="$GCC_HOME/bin:$PATH";;
esac
# Set CC/CXX only if no other compiler claimed them already (so clang wins when both installed)
: "${CC:=gcc}"
: "${CXX:=g++}"
export CC CXX
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- wrapper for non-login shells ----
cat >"$BIN_DIR/gccwrap" <<'EOF'
#!/bin/sh
: "${GCC_HOME:=/opt/gcc-stable}"
PATH="$GCC_HOME/bin:$PATH"
export GCC_HOME PATH
tool="$(basename "$0")"
exec "$GCC_HOME/bin/$tool" "$@"
EOF
chmod +x "$BIN_DIR/gccwrap"

# Common entrypoints (only create if not already pointing at clangwrap)
for t in gcc g++; do
  if [[ -L "$BIN_DIR/$t" && "$(readlink "$BIN_DIR/$t")" == *clangwrap* ]]; then
    echo "ℹ️ Skipping symlink $BIN_DIR/$t (held by clang); use update-alternatives or /opt/gcc-stable/bin"
    continue
  fi
  ln -sfn "$BIN_DIR/gccwrap" "$BIN_DIR/$t"
done

# ---- update-alternatives (lower priority than clang) ----
update-alternatives --install /usr/bin/cc  cc  "$TARGET_DIR/bin/gcc" 50
update-alternatives --install /usr/bin/c++ c++ "$TARGET_DIR/bin/g++" 50

# ---- summary ----
echo "✅ GCC ${GCC_VER} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   gcc --version → "; "$TARGET_DIR/bin/gcc" --version | head -n1 || true
echo -n "   g++ --version → "; "$TARGET_DIR/bin/g++" --version | head -n1 || true

cat <<'EON'
ℹ️ Ready to use:
- Try: gcc --version && g++ --version
- Works in login & non-login shells.
- CC and CXX default to gcc/g++ (deferred so clang wins if both installed).
- Registered with update-alternatives (priority 50). If Clang is installed at priority 100, it stays default.
EON
