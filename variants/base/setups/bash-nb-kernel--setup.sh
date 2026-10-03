#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# bash-nb-kernel--setup.sh
# 
# Prereqs:
#   - python--setup.sh and notebook--setup.sh already ran successfully.
#   - /etc/profile.d/53-cb-python--profile.sh should be source
#   - The chosen Python can install packages with pip.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------- Root & early checks ----------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root


# ---------------- Load environment from profile.d ----------------
# These set: PY_STABLE, PY_STABLE_VERSION, PY_SERIES, VENV_SERIES_DIR, PATH tweaks, etc.
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-bash}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Bash}"

# Exact pins (verified against PyPI 2026-10-02) -- a bare `-U` let these float
# to whatever PyPI served at build time; see notebook--setup.sh's own comment
# on why that's a real reproducibility gap, not a cosmetic one. Keep the
# pip/setuptools/wheel pins identical to notebook--setup.sh's -- both scripts
# run against the same interpreter, and this one runs after it.
PIP_PIN_VERSION="26.2.1"
SETUPTOOLS_PIN_VERSION="84.0.0"
WHEEL_PIN_VERSION="0.48.0"
JUPYTER_CLIENT_VERSION="8.10.0"
BASH_KERNEL_VERSION="0.10.0"


# Pick Python: prefer the venv’s python; else fall back to python3/python on PATH.
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter."
  exit 1
fi

# ---------------- Ensure deps in the chosen Python ----------------
env PIP_CACHE_DIR="$PIP_CACHE_DIR" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install \
    "pip==${PIP_PIN_VERSION}" "setuptools==${SETUPTOOLS_PIN_VERSION}" "wheel==${WHEEL_PIN_VERSION}" >/dev/null

env PIP_CACHE_DIR="$PIP_CACHE_DIR" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install \
    "jupyter_client==${JUPYTER_CLIENT_VERSION}" "bash_kernel==${BASH_KERNEL_VERSION}" >/dev/null

# ---------------- Register kernelspecs ----------------
echo "🧩 Registering Bash kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)…"
python -m bash_kernel.install --prefix "${JUPYTER_KERNEL_PREFIX}"

# If we have a venv, also install the kernelspec in that venv (sys-prefix)
echo "🧩 Also registering Bash kernel into venv: ${CB_VENV_DIR} (sys-prefix)…"
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
