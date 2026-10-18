#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# conda-nb-kernel--setup.sh
# Registers the booth's conda environment as its own Jupyter kernel.
#
# JupyterLab and its stock "python" kernel live in the uv venv that
# notebook--setup.sh froze at build time, so packages put into the conda env
# (`install conda rdkit`, `conda install ...`) are invisible to a notebook on
# that kernel. This adds a second kernel whose interpreter *is* the conda env.
#
# Prereqs:
#   - conda--setup.sh already ran (/opt/conda, env linked at /opt/python).
#   JupyterLab need not be installed yet: a kernelspec is only a directory
#   under /usr/local/share/jupyter/kernels, and notebook--setup.sh replaces
#   only its own "python" kernel there, so this one survives it either way.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [<kernel-name> [<display-name>]]

Examples:
  $0                          # kernel "conda", shown as "Python 3.13 (conda)"
  $0 chem "Chemistry (conda)"

Notes:
- Installs ipykernel into the conda env with conda, then registers it under
  /usr/local/share/jupyter/kernels/<kernel-name>.
- The kernel points at the env's real path, so a later relink of /opt/python
  does not change which interpreter a notebook gets.
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

# cb_retry: retry the conda install past a transient registry error only.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

CONDA_ROOT="/opt/conda"
CONDA_ENV_LINK="/opt/python"
JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"

# Matches IPYKERNEL_VERSION in notebook--setup.sh, so both kernels speak the
# same protocol and a rebuild cannot float to whatever conda-forge serves.
IPYKERNEL_VERSION="7.4.0"

# ---- sanity checks ----
# Not a skip: this kernel was selected on purpose, and without conda there is
# nothing to register -- the selection is wrong, so say how to fix it.
if [ ! -x "${CONDA_ROOT}/bin/conda" ]; then
  echo "❌ Conda is not installed. Select it too: python+conda+conda-kernel." >&2
  exit 1
fi
if [ ! -x "${CONDA_ENV_LINK}/bin/python" ]; then
  echo "❌ No conda env at ${CONDA_ENV_LINK}. Run conda--setup.sh first." >&2
  exit 1
fi

ENV_PATH="$(readlink -f "${CONDA_ENV_LINK}")"
if [ ! -d "${ENV_PATH}/conda-meta" ]; then
  echo "❌ ${CONDA_ENV_LINK} → ${ENV_PATH} is not a conda env (no conda-meta/)." >&2
  echo "   Was python--setup.sh run after conda--setup.sh? conda must come last." >&2
  exit 1
fi

PY_VERSION="$("${ENV_PATH}/bin/python" -c 'import sys;print(".".join(map(str,sys.version_info[:2])))')"
KERNEL_NAME="${1:-conda}"
KERNEL_DISPLAY_NAME="${2:-Python ${PY_VERSION} (conda)}"
KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"

# ---- install ipykernel into the conda env ----
echo "📦 Installing ipykernel ${IPYKERNEL_VERSION} into ${ENV_PATH} ..."
cb_retry "${CONDA_ROOT}/bin/conda" install -y -p "${ENV_PATH}" "ipykernel=${IPYKERNEL_VERSION}"

# ---- register the kernel ----
echo "🧩 Registering kernel '${KERNEL_NAME}' at ${KDIR} ..."
rm -rf "${KDIR}"
"${ENV_PATH}/bin/python" -m ipykernel install \
  --prefix="${JUPYTER_KERNEL_PREFIX}"          \
  --name="${KERNEL_NAME}"                      \
  --display-name="${KERNEL_DISPLAY_NAME}"
chmod -R a+rX "${KDIR}" || true

# ipykernel writes sys.executable -- the env's real path, because that is what
# ran it above -- so the kernel survives /opt/python being relinked later.
if ! grep -q "\"${ENV_PATH}/bin/python\"" "${KDIR}/kernel.json"; then
  echo "❌ ${KDIR}/kernel.json does not point at ${ENV_PATH}/bin/python:" >&2
  cat "${KDIR}/kernel.json" >&2
  exit 1
fi

# ---- keep `jupyter` meaning the notebook's Jupyter ----
# ipykernel pulls jupyter_core and jupyter_client into the conda env, and with
# them a bare `jupyter` CLI (kernel, kernelspec, run -- no lab, no nbconvert).
# The env's bin/ is first on PATH, so that stub would shadow the notebook's
# Jupyter in every terminal. The kernel needs only the Python modules, so drop
# the env's CLI wrappers and point `jupyter` at the notebook venv's own. A later
# `conda install` that upgrades jupyter_core brings the stub back; re-run this
# script, or call ${CB_NOTEBOOK_VENV_DIR}/bin/jupyter directly.
rm -f "${ENV_PATH}/bin/jupyter" "${ENV_PATH}"/bin/jupyter-*

[ -f /etc/profile.d/70-cb-notebook--profile.sh ] && source /etc/profile.d/70-cb-notebook--profile.sh 2>/dev/null || true
NOTEBOOK_JUPYTER="${CB_NOTEBOOK_VENV_DIR:-}/bin/jupyter"
if [ -n "${CB_NOTEBOOK_VENV_DIR:-}" ] && [ -x "${NOTEBOOK_JUPYTER}" ]; then
  ln -sfn "${NOTEBOOK_JUPYTER}" /usr/local/bin/jupyter
  echo "🔗 /usr/local/bin/jupyter → ${NOTEBOOK_JUPYTER}"
else
  echo "ℹ️  JupyterLab is not installed yet; \`jupyter\` is left to notebook--setup.sh."
fi

# ---- summary ----
echo "✅ Conda kernel installed."
echo "   Kernel name:    ${KERNEL_NAME}"
echo "   Display name:   ${KERNEL_DISPLAY_NAME}"
echo "   Interpreter:    ${ENV_PATH}/bin/python (Python ${PY_VERSION})"

cat <<EON
ℹ️ Ready to use:
- In JupyterLab: Kernel → Change Kernel… → "${KERNEL_DISPLAY_NAME}"
- jupyter kernelspec list
- conda install <pkg>   # then restart the kernel to import it
EON
