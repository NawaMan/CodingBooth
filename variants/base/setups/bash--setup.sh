#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y|X.Y.Z>]

Examples:
  $0                      # GNU Bash 3.2.57, installed as bash-3.2
  $0 --version 3.2.57     # same pin
  $0 --version 5.2.37     # installed as bash-5.2
  $0 --version 5.3        # installed as bash-5.3

Notes:
- Builds a GNU release from https://ftp.gnu.org/gnu/bash/
- Installs under /opt/bash/bash-<version>
- Links /usr/local/bin/bash-<major>.<minor> (and bash-<version> when that differs)
- Leaves /bin/bash, the image login shell, alone
- Bash 3.2 is the shell macOS ships as /bin/bash. Under set -u, "\${a[@]}"
  on an empty array is an error there. \${a[@]+"\${a[@]}"} is not.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

# ---- defaults / args ----
# Do not read $BASH_VERSION here. That name is bash's own version string
# (the shell running this script). The requested release arrives as --version.
BASH_DEFAULT_VER="3.2.57"
REQ_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

VERSION="${REQ_VER:-$BASH_DEFAULT_VER}"
if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
  echo "❌ Not a bash version: '${VERSION}' (expected X.Y or X.Y.Z, as in 3.2.57 or 5.3)" >&2
  usage
  exit 2
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
MM="${MAJOR}.${MINOR}"

# GCC 15 (Ubuntu 26.04) defaults to C23. Bash 3.x is K&R C and needs gnu89
# plus -fpermissive. Bash before 5.3 needs gnu17. 5.3 compiles as C23.
CFLAGS_PIN=""
if (( MAJOR < 4 )); then
  CFLAGS_PIN="-std=gnu89 -fpermissive"
elif (( MAJOR < 5 || (MAJOR == 5 && MINOR < 3) )); then
  CFLAGS_PIN="-std=gnu17"
fi

INSTALL_PARENT=/opt/bash
TARGET_DIR="${INSTALL_PARENT}/bash-${VERSION}"
BIN_DIR=/usr/local/bin

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential bison libncurses-dev curl ca-certificates
rm -rf /var/lib/apt/lists/*

mkdir -p /usr/local/src
TMP="$(mktemp -d /usr/local/src/bash-build.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

TARBALL="bash-${VERSION}.tar.gz"
URL="https://ftp.gnu.org/gnu/bash/${TARBALL}"
ALT_URL="https://ftpmirror.gnu.org/bash/${TARBALL}"

echo "⬇️  Downloading GNU Bash ${VERSION} ..."
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$TARBALL"; then
  echo "   Primary mirror failed, trying fallback mirror..."
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$ALT_URL" -o "$TMP/$TARBALL"
fi

echo "📦 Building GNU Bash ${VERSION} ..."
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

tar -xzf "$TMP/$TARBALL" -C "$TMP"
SRC_DIR="$TMP/bash-${VERSION}"
[[ -d "$SRC_DIR" ]] || { echo "❌ Expected source dir ${SRC_DIR}"; exit 1; }
cd "$SRC_DIR"

# The 3.2.57 tarball ships a y.tab.c from 2006. parse.y is newer and calls
# expand_prompt_string with three arguments. bison (installed above) regenerates
# the parser because parse.y is newer. Do not touch y.tab.c ahead of make.

if [[ -n "$CFLAGS_PIN" ]]; then
  export CFLAGS="$CFLAGS_PIN"
  export CFLAGS_FOR_BUILD="$CFLAGS_PIN"
fi

./configure --prefix="$TARGET_DIR" --without-bash-malloc

# Bash 3.2 races under make -j: two jobs write support/newversion.h and one
# mv fails. Build that line serially. Later releases take the core count.
if (( MAJOR < 4 )); then
  make -j1
else
  make -j"$(nproc)"
fi
make install

ln -sfn "${TARGET_DIR}/bin/bash" "${BIN_DIR}/bash-${MM}"
if [[ "$VERSION" != "$MM" ]]; then
  ln -sfn "${TARGET_DIR}/bin/bash" "${BIN_DIR}/bash-${VERSION}"
fi

# BASH_VERSION here is the shell we just installed. It looks like
# 3.2.57(1)-release. Drop the release suffix before comparing.
got="$("${BIN_DIR}/bash-${MM}" -c 'printf %s "$BASH_VERSION"')"
got="${got%%\(*}"
case "$got" in
  "$VERSION"|"${VERSION}".*) ;;
  *) echo "❌ Installed bash reports ${got}, wanted ${VERSION}" >&2; exit 1 ;;
esac

echo "✅ GNU Bash installed."
echo "   Version: ${VERSION} → ${TARGET_DIR}"
echo "   Command: bash-${MM}"
echo -n "   bash-${MM} --version → "
"${BIN_DIR}/bash-${MM}" --version | head -n1 || true

cat <<EON
ℹ️ Ready to use:
- bash-${MM} --version
- bash-${MM} ./script.sh

/bin/bash is still the image login shell. bash-${MM} is a second shell.
macOS ships Bash 3.2 as /bin/bash. Under set -u, "\${a[@]}" on an empty
array is an error there. \${a[@]+"\${a[@]}"} expands to nothing instead.
EON
