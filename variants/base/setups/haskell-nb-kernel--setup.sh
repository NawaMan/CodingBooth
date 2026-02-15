#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# haskell-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the IHaskell Jupyter kernel.
# IHaskell provides interactive Haskell in Jupyter notebooks.
#
# Prereqs:
#   - haskell--setup.sh already ran successfully (ghc, cabal on PATH).
#   - python--setup.sh and notebook--setup.sh already ran.
#   - /etc/profile.d/53-cb-python--profile.sh should be sourced.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Load environment from profile.d ----------------
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
source /etc/profile.d/99-haskell--profile.sh   2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-haskell}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Haskell (IHaskell)}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v ghc >/dev/null 2>&1; then
  echo "❌ GHC is not installed or not on PATH." >&2
  exit 1
fi

if ! command -v cabal >/dev/null 2>&1; then
  echo "❌ Cabal is not installed or not on PATH." >&2
  exit 1
fi

# Ensure python has jupyter_client and jupyter_core
if ! python - <<'PY' >/dev/null 2>&1
import importlib.util as u
raise SystemExit(0 if all(u.find_spec(m) for m in ("jupyter_client","jupyter_core")) else 1)
PY
then
  echo "❌ python lacks required Jupyter packages ('jupyter_client' and/or 'jupyter_core')." >&2
  exit 2
fi

# ---------------- Install build dependencies ----------------
echo "📦 Installing IHaskell build dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  pkg-config libmagic-dev libzmq5 libzmq3-dev libtinfo-dev
rm -rf /var/lib/apt/lists/*

# ---------------- Install IHaskell ----------------
echo "📦 Installing IHaskell via cabal..."
cabal update
HASKELL_HOME="${HASKELL_HOME:-/opt/haskell-stable}"
mkdir -p "${HASKELL_HOME}/.cabal/bin"
cabal install ihaskell --overwrite-policy=always \
  --installdir="${HASKELL_HOME}/.cabal/bin" \
  --install-method=copy

IHASKELL_BIN="${HASKELL_HOME}/.cabal/bin/ihaskell"
if [ ! -x "${IHASKELL_BIN}" ]; then
  echo "❌ ihaskell binary not found at ${IHASKELL_BIN}" >&2
  exit 1
fi

# ---------------- Create kernelspec manually ----------------
TMPKDIR="$(mktemp -d)/haskell"
mkdir -p "${TMPKDIR}"

cat > "${TMPKDIR}/kernel.json" <<KJSON
{
  "argv": ["${IHASKELL_BIN}", "kernel", "{connection_file}", "--stack"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "haskell",
  "metadata": {
    "kernel_info": {
      "description": "Haskell (IHaskell) Jupyter kernel"
    }
  }
}
KJSON

# ---------------- Register kernelspec system-wide ----------------
echo "🧩 Registering Haskell kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
python -m jupyter kernelspec install "${TMPKDIR}" \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --replace \
  --name="${KERNEL_NAME}"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Haskell (IHaskell) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   IHaskell binary:  ${IHASKELL_BIN}"
