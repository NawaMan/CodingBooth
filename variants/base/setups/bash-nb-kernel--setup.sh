#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# bash-nb-kernel--setup.sh
# 
# Prereqs:
#   - python--setup.sh and notebook--setup.sh already ran successfully.
#   - /etc/profile.d/53-ws-python--profile.sh should be source
#   - The chosen Python can install packages with pip.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# ---------------- Load environment from profile.d ----------------
# These set: PY_STABLE, PY_STABLE_VERSION, PY_SERIES, VENV_SERIES_DIR, PATH tweaks, etc.
source /etc/profile.d/53-ws-python--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-bash}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Bash}"


# Pick Python: prefer the venv’s python; else fall back to python3/python on PATH.
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter."
  exit 1
fi

# ---------------- Ensure deps in the chosen Python ----------------
env PIP_CACHE_DIR="$PIP_CACHE_DIR" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install -U pip setuptools wheel >/dev/null

env PIP_CACHE_DIR="$PIP_CACHE_DIR" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install -U jupyter_client bash_kernel >/dev/null

# ---------------- Register kernelspecs ----------------
echo "🧩 Registering Bash kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)…"
python -m bash_kernel.install --prefix "${JUPYTER_KERNEL_PREFIX}"

# If we have a venv, also install the kernelspec in that venv (sys-prefix)
echo "🧩 Also registering Bash kernel into venv: ${WS_VENV_DIR} (sys-prefix)…"
python -m bash_kernel.install --sys-prefix || true


# Expected system-wide kernelspec dir
KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
[ -d "${KDIR}" ] || echo "ℹ️ Could not confirm ${KDIR}; listing kernels below for verification."

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Bash kernel installed."
[ -n "${KDIR:-}" ] && echo "   System kernelspec dir: ${KDIR}"
echo "   Display name: ${KERNEL_DISPLAY_NAME}"

echo
echo "Use it now in this shell:"
echo "  jupyter kernelspec list | sed -n '1,10p'"
