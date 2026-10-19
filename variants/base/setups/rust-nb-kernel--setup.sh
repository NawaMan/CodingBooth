#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

# rust-nb-kernel--setup.sh
#
# Installs the Evcxr Jupyter kernel for Rust.
# Evcxr provides an interactive Rust REPL in Jupyter notebooks.
#
# evcxr_jupyter (EVCXR_VERSION, default 0.22.0) comes prebuilt (sha256-checked) from
# https://github.com/NawaMan/CodingBoothPrebuilt/releases for x86_64 and arm64;
# any other version, Ubuntu or CPU is compiled with `cargo install`.
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
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# Load Rust/Cargo environment
[ -f /root/.cargo/env ] && source /root/.cargo/env

# ---------------- Defaults / Tunables ----------------
EVCXR_VERSION="${EVCXR_VERSION:-0.22.0}"
EVCXR_DIR="/opt/evcxr/evcxr_jupyter-${EVCXR_VERSION}"
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
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

rm -rf "${EVCXR_DIR}"
if ! cb_prebuilt_install evcxr_jupyter "${EVCXR_VERSION}" native "${EVCXR_DIR}"; then
  echo "📦 Compiling evcxr_jupyter ${EVCXR_VERSION} with cargo (this takes several minutes)..."
  cargo install --locked evcxr_jupyter --version "=${EVCXR_VERSION}" --root "${EVCXR_DIR}"
fi
chmod -R a+rX "${EVCXR_DIR}"

EVCXR_BIN="${EVCXR_DIR}/bin/evcxr_jupyter"
if [ ! -x "${EVCXR_BIN}" ]; then
  echo "❌ evcxr_jupyter binary not found at ${EVCXR_BIN}." >&2
  exit 1
fi
ln -sfn "${EVCXR_BIN}" /usr/local/bin/evcxr_jupyter

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
