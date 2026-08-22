#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# lua-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the ILua Jupyter kernel for Lua.
# ILua is a pip-based Lua kernel that delegates to the lua interpreter.
#
# Prereqs:
#   - lua--setup.sh already ran (lua on PATH).
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
KERNEL_NAME="${KERNEL_NAME:-lua}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Lua}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v lua >/dev/null 2>&1; then
  echo "❌ Lua is not installed or not on PATH." >&2
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

# ---------------- Install ILua (pip-based) ----------------
echo "📦 Installing ILua into VENV..."
env PIP_CACHE_DIR="${PIP_CACHE_DIR}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install -U ilua >/dev/null

# ---------------- Create kernelspec manually ----------------
# ILua doesn't have a clean --prefix install; create kernelspec for our prefix.
ILUA_BIN="$(command -v ilua 2>/dev/null || true)"
if [ -z "${ILUA_BIN}" ]; then
  # Try finding it in the VENV bin
  ILUA_BIN="${CB_VENV_DIR}/bin/ilua"
fi

if [ ! -x "${ILUA_BIN}" ]; then
  echo "❌ ilua binary not found after pip install." >&2
  exit 1
fi

TMPKDIR="$(mktemp -d)/lua"
mkdir -p "${TMPKDIR}"

cat > "${TMPKDIR}/kernel.json" <<KJSON
{
  "argv": ["${ILUA_BIN}", "-c", "{connection_file}"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "lua",
  "metadata": {
    "kernel_info": {
      "description": "Lua (ILua) Jupyter kernel"
    }
  }
}
KJSON

# ---------------- Register kernelspec system-wide ----------------
echo "🧩 Registering Lua kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
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
echo "✅ Lua (ILua) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   ILua binary:      ${ILUA_BIN}"
