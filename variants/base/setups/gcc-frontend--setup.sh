#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# Adds one GCC language front end (Fortran, COBOL, ALGOL 68) beside the gcc setup.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 --lang <fortran|cobol|algol68> [--version <N>]

Examples:
  $0 --lang fortran                # gfortran-15
  $0 --lang cobol --version 16     # gcobol-16
  $0 --lang algol68                # ga68-15

Notes:
- Installs the distro's <tool>-<N> package (gfortran / gcobol / ga68)
- Links it into /opt/gcc/gcc-<N>/bin, beside gcc and g++ from the gcc setup,
  so /opt/gcc-stable/bin and /usr/local/bin both find it
- <N> should match the gcc setup's --version; gcobol and ga68 exist from GCC 15
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
GCC_DEFAULT=15
REQ_VER=""
LANG_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang)    shift; LANG_NAME="${1:-}"; shift ;;
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

GCC_VER="${REQ_VER:-$GCC_DEFAULT}"

case "$LANG_NAME" in
  fortran) TOOL=gfortran; LABEL="GNU Fortran" ;;
  cobol)   TOOL=gcobol;   LABEL="GCC COBOL"   ;;
  algol68) TOOL=ga68;     LABEL="GCC ALGOL 68" ;;
  "")      echo "❌ --lang is required" >&2; usage; exit 2 ;;
  *)       echo "❌ Unknown language: $LANG_NAME (fortran, cobol or algol68)" >&2; exit 2 ;;
esac

PKG="${TOOL}-${GCC_VER}"

# ---- check availability ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
if ! apt-cache show "$PKG" >/dev/null 2>&1; then
  echo "❌ $PKG is not available in this distribution (gcobol and ga68 need GCC 15 or later)." >&2
  exit 1
fi

echo "📦 Installing ${LABEL} (${PKG}) ..."
apt-get install -y --no-install-recommends "$PKG"
rm -rf /var/lib/apt/lists/*

# ---- dirs ----
INSTALL_PARENT=/opt/gcc
TARGET_DIR="${INSTALL_PARENT}/gcc-${GCC_VER}"
LINK_DIR=/opt/gcc-stable
BIN_DIR=/usr/local/bin

mkdir -p "$TARGET_DIR/bin"
ln -sfn "$(command -v "$PKG")" "$TARGET_DIR/bin/$TOOL"

# The gcc setup owns /opt/gcc-stable; only claim it when nothing else has.
[[ -e "$LINK_DIR" ]] || ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- non-login shells ----
ln -sfn "$LINK_DIR/bin/$TOOL" "$BIN_DIR/$TOOL"

if [[ "$TOOL" == ga68 && "$GCC_VER" -lt 16 ]]; then
  echo "⚠️  ga68 ${GCC_VER} is an early cut: it cannot yet compile parts of the standard prelude" >&2
  echo "    (whole, for one). Use --version 16 (template: gcc:16) for working ALGOL 68." >&2
fi

# ---- summary ----
echo "✅ ${LABEL} ${GCC_VER} installed at ${TARGET_DIR}/bin/${TOOL}."
echo -n "   ${TOOL} --version → "; "$TARGET_DIR/bin/$TOOL" --version | head -n1 || true

case "$TOOL" in
  gfortran) cat <<'EON'
ℹ️ Ready to use:
- gfortran hello.f90 -o hello && ./hello
EON
  ;;
  gcobol) cat <<'EON'
ℹ️ Ready to use:
- gcobol hello.cob -o hello && ./hello
EON
  ;;
  ga68) cat <<'EON'
ℹ️ Ready to use:
- ga68 hello.a68 -o hello && ./hello
EON
  ;;
esac
