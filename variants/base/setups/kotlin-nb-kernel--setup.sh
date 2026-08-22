#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# kotlin-nb-kernel--setup.sh
#
# Installs the Kotlin Jupyter kernel (JetBrains official, pip-based).
# This is a pip package that wraps a JVM-based kernel.
#
# Prereqs:
#   - kotlin--setup.sh already ran (JDK on PATH for the kernel runtime).
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
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-kotlin}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Kotlin}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v java >/dev/null 2>&1; then
  echo "❌ Java is not installed or not on PATH (required by Kotlin kernel)." >&2
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

# ---------------- Install Kotlin kernel (pip-based) ----------------
echo "📦 Installing kotlin-jupyter-kernel into VENV..."
env PIP_CACHE_DIR="${PIP_CACHE_DIR}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install -U kotlin-jupyter-kernel >/dev/null

# ---------------- Register kernelspec ----------------
# The kotlin-jupyter-kernel pip package provides `python -m kotlin_kernel` with subcommands:
#   add-kernel              — register a kernel (installs to Jupyter data dir)
#   fix-kernelspec-location — fix the kernelspec path after pip install
# We register via add-kernel, then copy to the system prefix for all users.
echo "🧩 Registering Kotlin kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"

# Step 1: Fix kernelspec location (recommended after pip install)
python -m kotlin_kernel fix-kernelspec-location 2>/dev/null || true

# Step 2: Try to find the kernelspec that was installed by pip
FOUND_KDIR="$(python -m jupyter kernelspec list 2>/dev/null | grep -i kotlin | awk '{print $2}' || true)"

if [ -z "${FOUND_KDIR}" ] || [ ! -d "${FOUND_KDIR}" ]; then
  # No kernelspec found yet — use add-kernel to create one
  echo "ℹ️  Running kotlin_kernel add-kernel..."
  python -m kotlin_kernel add-kernel --name "${KERNEL_NAME}" || true
  FOUND_KDIR="$(python -m jupyter kernelspec list 2>/dev/null | grep -i kotlin | awk '{print $2}' || true)"
fi

if [ -n "${FOUND_KDIR}" ] && [ -d "${FOUND_KDIR}" ]; then
  # Copy to the system prefix if it was installed elsewhere
  if [ "${FOUND_KDIR}" != "${KDIR}" ]; then
    mkdir -p "$(dirname "${KDIR}")"
    rm -rf "${KDIR}"
    cp -a "${FOUND_KDIR}" "${KDIR}"
  fi
else
  echo "❌ Failed to register Kotlin kernel — no kernelspec found." >&2
  exit 1
fi

# Stamp display name if needed
if [ -f "${KDIR}/kernel.json" ]; then
  python - "${KDIR}/kernel.json" "${KERNEL_DISPLAY_NAME}" <<'PY'
import json, sys
path, display = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data["display_name"] = display
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
fi

chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Kotlin kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
