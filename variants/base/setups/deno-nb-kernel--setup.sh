#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# deno-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the built-in Deno Jupyter kernel.
# Deno has native Jupyter support via `deno jupyter --install`.
#
# Prereqs:
#   - deno--setup.sh already ran (deno on PATH).
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
KERNEL_NAME="${KERNEL_NAME:-deno}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Deno}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v deno >/dev/null 2>&1; then
  echo "❌ Deno is not installed or not on PATH." >&2
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

# ---------------- Create kernelspec manually ----------------
# `deno jupyter --install` writes to user data dir. We create for our prefix.
DENO_BIN="$(command -v deno)"
TMPKDIR="$(mktemp -d)/deno"
mkdir -p "${TMPKDIR}"

cat > "${TMPKDIR}/kernel.json" <<KJSON
{
  "argv": ["${DENO_BIN}", "jupyter", "--kernel", "--conn", "{connection_file}"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "typescript",
  "metadata": {
    "kernel_info": {
      "description": "Deno (built-in) Jupyter kernel"
    }
  }
}
KJSON

# ---------------- Register kernelspec system-wide ----------------
echo "🧩 Registering Deno kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
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
echo "✅ Deno kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   Deno binary:      ${DENO_BIN}"
echo "   Deno version:     $(deno --version 2>/dev/null | head -1 || echo 'unknown')"
