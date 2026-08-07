#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# octave-nb-kernel--setup.sh
#
# Installs the Calysto Octave Jupyter kernel.
# octave_kernel is a pip-installable Jupyter kernel that delegates to octave-cli.
#
# Prereqs:
#   - octave--setup.sh already ran successfully (octave-cli on PATH).
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
KERNEL_NAME="${KERNEL_NAME:-octave}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Octave}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v octave-cli >/dev/null 2>&1 && ! command -v octave >/dev/null 2>&1; then
  echo "❌ Octave is not installed or not on PATH." >&2
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

# ---------------- Install octave_kernel (pip-based) ----------------
echo "📦 Installing octave_kernel into venv..."
env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  python -m pip install -U octave_kernel

# ---------------- Register kernelspec system-wide ----------------
echo "🧩 Registering Octave kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
mkdir -p "${KDIR}"

PYTHON_BIN="$(command -v python)"

cat > "${KDIR}/kernel.json" <<KJSON
{
  "argv": ["${PYTHON_BIN}", "-m", "octave_kernel", "-f", "{connection_file}"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "octave"
}
KJSON

chmod -R a+rX "${KDIR}" 2>/dev/null || true

# ---------------- Configure gnuplot for inline plotting ----------------
# In containers (notebook variant) there is no display server, so gnuplot is
# the graphics toolkit to draw with. But the toolkit name alone is not enough:
# octave_kernel only captures figures and returns them as notebook images when
# the backend starts with "inline". A bare 'gnuplot' means "draw live", and
# with no display gnuplot falls back to its ASCII "dumb" terminal, which lands
# in the cell as unreadable text art. 'inline:gnuplot' picks the toolkit *and*
# keeps inline capture on, so cells get a real PNG.
JUPYTER_CONFIG_DIR="${JUPYTER_KERNEL_PREFIX}/etc/jupyter"
mkdir -p "${JUPYTER_CONFIG_DIR}"
cat > "${JUPYTER_CONFIG_DIR}/octave_kernel_config.py" <<'PYCONF'
c.OctaveKernel.plot_settings = dict(backend='inline:gnuplot', format='png')
PYCONF
chmod 0644 "${JUPYTER_CONFIG_DIR}/octave_kernel_config.py"

# ---------------- Verification ----------------
echo
echo "🔎 Kernels:"
python -m jupyter kernelspec list || true

# ---------------- Friendly summary ----------------
echo
echo "✅ Octave (Calysto) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
OCT_VER="$(octave-cli --version 2>/dev/null | head -1 || echo 'unknown')"
echo "   Octave version:   ${OCT_VER}"
