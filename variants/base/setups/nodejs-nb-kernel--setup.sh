#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# nodejs-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the tslab Jupyter kernel for Node.js / TypeScript.
# tslab provides JavaScript and TypeScript REPLs in Jupyter.
#
# Prereqs:
#   - nodejs--setup.sh already ran (node/npm on PATH).
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
KERNEL_NAME="${KERNEL_NAME:-javascript}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-JavaScript (Node.js)}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "❌ Node.js is not installed or not on PATH." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "❌ npm is not installed or not on PATH." >&2
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

# ---------------- Install tslab ----------------
echo "📦 Installing tslab globally..."
npm install -g tslab

TSLAB_BIN="$(command -v tslab 2>/dev/null || true)"
if [ -z "${TSLAB_BIN}" ]; then
  echo "❌ tslab binary not found after npm install." >&2
  exit 1
fi

# ---------------- Create kernelspec manually ----------------
# tslab install writes to user/sys data dir. We create kernelspec for our prefix.
TMPKDIR_JS="$(mktemp -d)/javascript"
mkdir -p "${TMPKDIR_JS}"

NODE_BIN="$(command -v node)"

cat > "${TMPKDIR_JS}/kernel.json" <<KJSON
{
  "argv": ["${TSLAB_BIN}", "kernel", "--config-path", "{connection_file}"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "javascript",
  "metadata": {
    "kernel_info": {
      "description": "JavaScript/TypeScript (tslab) Jupyter kernel"
    }
  }
}
KJSON

# Also register a TypeScript kernel
TMPKDIR_TS="$(mktemp -d)/typescript"
mkdir -p "${TMPKDIR_TS}"

cat > "${TMPKDIR_TS}/kernel.json" <<KJSON
{
  "argv": ["${TSLAB_BIN}", "kernel", "--config-path", "{connection_file}"],
  "display_name": "TypeScript (Node.js)",
  "language": "typescript",
  "metadata": {
    "kernel_info": {
      "description": "TypeScript (tslab) Jupyter kernel"
    }
  }
}
KJSON

# ---------------- Register kernelspecs system-wide ----------------
echo "🧩 Registering JavaScript kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
python -m jupyter kernelspec install "${TMPKDIR_JS}" \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --replace \
  --name="${KERNEL_NAME}"

echo "🧩 Registering TypeScript kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
python -m jupyter kernelspec install "${TMPKDIR_TS}" \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --replace \
  --name="typescript"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
chmod -R a+rX "${KDIR}" 2>/dev/null || true
chmod -R a+rX "${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/typescript" 2>/dev/null || true

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ JavaScript/TypeScript (tslab) kernels installed."
echo "   JS kernel name:   ${KERNEL_NAME}"
echo "   TS kernel name:   typescript"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   tslab binary:     ${TSLAB_BIN}"
echo "   Node.js:          $(node --version 2>/dev/null || echo 'unknown')"
