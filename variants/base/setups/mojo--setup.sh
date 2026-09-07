#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# mojo--setup.sh — Install the Mojo compiler into the booth Python venv.
# Mojo 1.0 ships as a pip package (compiler, stdlib, LSP, LLDB). It needs
# Python 3.10–3.14 (python--setup.sh) and a C++ compiler on Linux.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                      # install Mojo 1.0.0 (current stable)
  $0 --version 1.0.0      # pin a release
  $0 --version latest     # newest PyPI release

Notes:
- Requires python--setup.sh first (the python template; auto-pulled by requires).
- Mojo needs Python 3.10–3.14. The booth Python default (3.13) is in range.
- Installs g++ (Mojo's Linux requirement) and pip-installs into /opt/python.
- Exposes 'mojo' via /usr/local/bin so a non-login shell (booth -- cmd) finds it.
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

# Overridable for host-side setups tests; production uses the booth venv.
CB_PYTHON_HOME="${CB_PYTHON_HOME:-/opt/python}"
CB_MOJO_BIN_DIR="${CB_MOJO_BIN_DIR:-/usr/local/bin}"

MOJO_DEFAULT_VER="1.0.0"
REQ_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

MOJO_VER="${REQ_VER:-$MOJO_DEFAULT_VER}"

PY="${CB_PYTHON_HOME}/bin/python"
if [[ ! -x "$PY" ]]; then
  echo "❌ Python is not set up. Run python--setup.sh first (select the python template)." >&2
  exit 1
fi

if ! "$PY" -c 'import sys; raise SystemExit(0 if (3, 10) <= sys.version_info[:2] <= (3, 14) else 1)'; then
  ver="$("$PY" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
  echo "❌ Mojo requires Python 3.10–3.14; found ${ver} at ${PY}" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends g++
rm -rf /var/lib/apt/lists/*

echo "⬇️  Installing Mojo ${MOJO_VER} into ${CB_PYTHON_HOME} ..."
if [[ "$MOJO_VER" == "latest" ]]; then
  cb_retry "$PY" -m pip install --upgrade mojo
else
  cb_retry "$PY" -m pip install "mojo==${MOJO_VER}"
fi

MOJO_BIN="${CB_PYTHON_HOME}/bin/mojo"
if [[ ! -x "$MOJO_BIN" ]]; then
  echo "❌ pip installed mojo but ${MOJO_BIN} is not executable" >&2
  exit 1
fi

install -d "$CB_MOJO_BIN_DIR"
ln -sfn "$MOJO_BIN" "${CB_MOJO_BIN_DIR}/mojo"

INSTALLED="$("$MOJO_BIN" --version 2>/dev/null | head -1 || echo "${MOJO_VER}")"

echo "✅ Mojo installed."
echo "• Version: ${INSTALLED}"
echo "• Package: mojo==${MOJO_VER} (in ${CB_PYTHON_HOME})"
echo "• Command: ${CB_MOJO_BIN_DIR}/mojo -> ${MOJO_BIN}"
echo ""
echo "ℹ️ Ready to use:"
cat <<'EOF'
  mojo --version
  mojo hello.mojo          # JIT-compile and run
  mojo build hello.mojo    # emit an executable
EOF
