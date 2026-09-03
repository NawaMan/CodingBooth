#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Conda (Miniforge) setup script

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--python-version <x.y>]

Examples:
  $0                        # Miniforge with default Python
  $0 --python-version 3.11  # create env with Python 3.11

Notes:
- Installs Miniforge to /opt/conda
- Shared envs at /opt/conda-envs, package cache at /opt/conda-pkgs
- Creates a default env at /opt/python for consistency with python--setup.sh
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "Run as root (use sudo)"; exit 1; }

# ---- defaults / args ----
PY_VERSION="${1:-3.12}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python-version) shift; PY_VERSION="${1:-3.12}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) shift ;;  # positional arg for python version
  esac
done

ENV_NAME="py${PY_VERSION//./}"

# ---- locations ----
CONDA_PREFIX="/opt/conda"
CONDA_ENVS_DIR="/opt/conda-envs"
CONDA_PKGS_DIR="/opt/conda-pkgs"
PIP_CACHE_DIR="/opt/pip-cache"
ENV_PATH="${CONDA_ENVS_DIR}/${ENV_NAME}"
STABLE_PY_LINK="/opt/python"
PROFILE_FILE="/etc/profile.d/53-cb-conda--profile.sh"

# Set up env vars for this script
export CONDA_PKGS_DIRS="$CONDA_PKGS_DIR"
export CONDA_ENVS_DIRS="$CONDA_ENVS_DIR"

# ---- helpers ----
enforce_shared_perms() {
  mkdir -p "$CONDA_ENVS_DIR" "$CONDA_PKGS_DIR" "$PIP_CACHE_DIR"
  chmod 1777 "$CONDA_ENVS_DIR" "$CONDA_PKGS_DIR" "$PIP_CACHE_DIR"
  mkdir -p "${CONDA_PREFIX}/pkgs"
  chmod 1777 "${CONDA_PREFIX}/pkgs"
}

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl bzip2 ca-certificates
rm -rf /var/lib/apt/lists/*

mkdir -p "$CONDA_PREFIX"
chmod 0755 "$CONDA_PREFIX"

enforce_shared_perms

# ---- detect arch for Miniforge ----
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)         MARCH="x86_64" ;;
  aarch64|arm64)  MARCH="aarch64" ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 2 ;;
esac

# ---- install or reuse Miniforge ----
if [ -x "${CONDA_PREFIX}/bin/conda" ]; then
  echo "Found existing conda at ${CONDA_PREFIX} - reusing."
else
  echo "Downloading Miniforge for ${MARCH}..."
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o /tmp/miniforge.sh \
    "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${MARCH}.sh"

  INSTALL_FLAGS="-b -p ${CONDA_PREFIX}"
  [ -d "${CONDA_PREFIX}" ] && INSTALL_FLAGS="-b -u -p ${CONDA_PREFIX}"

  bash /tmp/miniforge.sh ${INSTALL_FLAGS}
  rm -f /tmp/miniforge.sh
fi

enforce_shared_perms

CONDA_BIN="${CONDA_PREFIX}/bin/conda"

# ---- conda config ----
"${CONDA_BIN}" config --system --set channel_priority strict
"${CONDA_BIN}" config --system --add channels conda-forge 2>/dev/null || true
"${CONDA_BIN}" config --system --set auto_update_conda false
"${CONDA_BIN}" config --system --set always_yes true

# ---- create the env (idempotent) ----
if [ -d "${ENV_PATH}" ]; then
  echo "Env '${ENV_NAME}' already exists at ${ENV_PATH} - skipping creation."
else
  echo "Creating Conda env '${ENV_NAME}' at ${ENV_PATH} with Python ${PY_VERSION} ..."
  "${CONDA_BIN}" create -p "${ENV_PATH}" "python=${PY_VERSION}" pip
fi

# ---- stable symlink ----
ln -snf "$ENV_PATH" "$STABLE_PY_LINK"

# Convenience shims
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip    || true

# ---- system-wide profile ----
cat >"$PROFILE_FILE" <<'EOF'
# Conda defaults (managed by conda--setup.sh)
export CONDA_PREFIX="/opt/conda"

# Ensure conda CLI is on PATH
if [ -d "${CONDA_PREFIX}/bin" ]; then
  case ":$PATH:" in *":${CONDA_PREFIX}/bin:"*) : ;; *)
    export PATH="${CONDA_PREFIX}/bin:${PATH}"
  esac
fi

# Source conda.sh for shell integration
if [ -f "${CONDA_PREFIX}/etc/profile.d/conda.sh" ]; then
  . "${CONDA_PREFIX}/etc/profile.d/conda.sh"
fi

# Shared caches/dirs
export CONDA_ENVS_DIRS="/opt/conda-envs"
export CONDA_PKGS_DIRS="/opt/conda-pkgs"
export PIP_CACHE_DIR="/opt/pip-cache"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1

# Stable Python location
export PY_STABLE="/opt/python"
if [ -d "${PY_STABLE}/bin" ]; then
  case ":$PATH:" in
    *":${PY_STABLE}/bin:"*) : ;;
    *) export PATH="${PY_STABLE}/bin:${PATH}" ;;
  esac
fi

# Don't auto-activate base
export CONDA_AUTO_ACTIVATE_BASE=false
EOF
chmod 0644 "$PROFILE_FILE"

# ---- summary ----
"${CONDA_PREFIX}/bin/conda" --version || true
"${STABLE_PY_LINK}/bin/python" -V || true
echo "Conda present at ${CONDA_PREFIX}"
echo "Shared envs root at ${CONDA_ENVS_DIR}, pkgs cache at ${CONDA_PKGS_DIR}"
echo "Env '${ENV_NAME}' at ${ENV_PATH}"
echo "Stable Python symlink at ${STABLE_PY_LINK}"

cat <<'EON'
Ready to use:
- conda --version
- python --version
- conda activate <env>
- conda install <package>
EON
