#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# r-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the IRkernel Jupyter kernel for R.
# IRkernel is the official R kernel for Jupyter.
#
# Prereqs:
#   - r-rscript--setup.sh already ran successfully (R/Rscript on PATH).
#   - python--setup.sh and notebook--setup.sh already ran.
#   - /etc/profile.d/53-cb-python--profile.sh should be sourced.

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

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-ir}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-R}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v R >/dev/null 2>&1; then
  echo "❌ R is not installed or not on PATH." >&2
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

# ---------------- Install IRkernel R package ----------------
echo "📦 Installing IRkernel R package..."
R --slave -e "install.packages('IRkernel', repos='https://cloud.r-project.org', quiet=TRUE)"

# ---------------- Register kernelspec ----------------
# IRkernel::installspec() natively supports prefix — very clean!
echo "🧩 Registering R kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
R --slave -e "IRkernel::installspec(name='${KERNEL_NAME}', displayname='${KERNEL_DISPLAY_NAME}', prefix='${JUPYTER_KERNEL_PREFIX}')"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ R (IRkernel) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
R_VER="$(R --version 2>/dev/null | head -1 || echo 'unknown')"
echo "   R version:        ${R_VER}"
