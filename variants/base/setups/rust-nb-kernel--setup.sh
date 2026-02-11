#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# rust-nb-kernel--setup.sh
# NOTE: This script has not been tested -- no time (sorry). Please report success or failure. :-p
#
# Installs the Evcxr Jupyter kernel for Rust.
# Evcxr provides an interactive Rust REPL in Jupyter notebooks.
#
# Prereqs:
#   - rust--setup.sh already ran successfully (cargo/rustc on PATH).
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

# Load Rust/Cargo environment
[ -f /root/.cargo/env ] && source /root/.cargo/env

# ---------------- Defaults / Tunables ----------------
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-rust}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Rust (Evcxr)}"

# ---------------- Sanity checks ----------------
if ! command -v python >/dev/null 2>&1; then
  echo "❌ Could not find any Python interpreter." >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "❌ Cargo is not installed or not on PATH." >&2
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

# ---------------- Install Evcxr ----------------
echo "📦 Installing evcxr_jupyter (this may take a while — it compiles from source)..."
cargo install --locked evcxr_jupyter

EVCXR_BIN="${CARGO_HOME:-$HOME/.cargo}/bin/evcxr_jupyter"
if [ ! -x "${EVCXR_BIN}" ]; then
  # Try finding it on PATH
  EVCXR_BIN="$(command -v evcxr_jupyter 2>/dev/null || true)"
  if [ -z "${EVCXR_BIN}" ]; then
    echo "❌ evcxr_jupyter binary not found after cargo install." >&2
    exit 1
  fi
fi

# ---------------- Create kernelspec manually ----------------
# We create the kernelspec ourselves for reliable prefix-based install.
TMPKDIR="$(mktemp -d)/rust"
mkdir -p "${TMPKDIR}"

cat > "${TMPKDIR}/kernel.json" <<KJSON
{
  "argv": ["${EVCXR_BIN}", "--control_file", "{connection_file}"],
  "display_name": "${KERNEL_DISPLAY_NAME}",
  "language": "rust",
  "metadata": {
    "kernel_info": {
      "description": "Rust (Evcxr) Jupyter kernel"
    }
  }
}
KJSON

# ---------------- Register kernelspec system-wide ----------------
echo "🧩 Registering Rust kernel under ${JUPYTER_KERNEL_PREFIX} (system-wide)..."
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
echo "✅ Rust (Evcxr) kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   Evcxr binary:     ${EVCXR_BIN}"
