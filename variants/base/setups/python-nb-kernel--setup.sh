#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# python-nb-kernel--setup.sh
#
# Registers the current Python (from python--setup.sh) as a Jupyter kernel.
# This allows users to install a new Python version and add it as a notebook kernel.
#
# Prereqs:
#   - python--setup.sh already ran successfully.
#   - notebook--setup.sh already ran (Jupyter is available).
#   - /etc/profile.d/53-cb-python--profile.sh should be sourced.
#
# Usage:
#   python-nb-kernel--setup.sh [kernel-name] [display-name]
#
# Examples:
#   python-nb-kernel--setup.sh                    # Auto-generates name from version
#   python-nb-kernel--setup.sh python313 "Python 3.13"

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
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
source /etc/profile.d/70-cb-notebook--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"

# Get current Python version
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter."
  exit 1
fi

PY_VERSION="${CB_PY_VERSION:-$(python -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')}"
PY_SERIES="${CB_PY_SERIES:-$(echo "$PY_VERSION" | cut -d. -f1-2)}"
VENV_DIR="${CB_VENV_DIR:-/opt/venvs/py${PY_VERSION}}"

# Kernel naming: default to pythonXY (e.g., python313) to avoid conflicts
KERNEL_NAME="${1:-python${PY_SERIES//./}}"
KERNEL_DISPLAY_NAME="${2:-Python ${PY_VERSION}}"

# ---------------- Idempotent check ----------------
# Key: kernel name. If name + python + display name all match, skip. Otherwise overwrite.
KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
KERNEL_JSON="${KDIR}/kernel.json"
EXPECTED_PY="${VENV_DIR}/bin/python"

if [ -f "${KERNEL_JSON}" ]; then
  # Check if kernel.json matches both Python path and display name
  if grep -q "\"${EXPECTED_PY}\"" "${KERNEL_JSON}" 2>/dev/null && \
     grep -q "\"display_name\": \"${KERNEL_DISPLAY_NAME}\"" "${KERNEL_JSON}" 2>/dev/null; then
    echo "✅ Kernel '${KERNEL_NAME}' already registered (Python ${PY_VERSION}, ${KERNEL_DISPLAY_NAME})"
    exit 0
  fi
fi

echo "🐍 Registering Python ${PY_VERSION} as Jupyter kernel..."
echo "   Kernel name:    ${KERNEL_NAME}"
echo "   Display name:   ${KERNEL_DISPLAY_NAME}"
echo "   Venv:           ${VENV_DIR}"

# ---------------- Ensure ipykernel in the target venv ----------------
if [ ! -x "${VENV_DIR}/bin/python" ]; then
  echo "❌ Python venv not found at ${VENV_DIR}"
  exit 1
fi

echo "📦 Installing ipykernel in ${VENV_DIR}..."
env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "${VENV_DIR}/bin/pip" install -U ipykernel >/dev/null

# ---------------- Register kernelspec ----------------
KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"

echo "🧩 Registering kernel at ${KDIR}..."
"${VENV_DIR}/bin/python" -m ipykernel install \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --name="${KERNEL_NAME}" \
  --display-name="${KERNEL_DISPLAY_NAME}"

chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Available kernels:"
python -m jupyter kernelspec list 2>/dev/null || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Python ${PY_VERSION} kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo
echo "Refresh the Jupyter Notebook page to see the new kernel."
