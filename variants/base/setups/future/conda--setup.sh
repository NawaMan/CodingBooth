#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args (safe defaults) ----
PY_VERSION=${1:-3.12}            # e.g. 3.12, 3.11, 3.10
ENV_NAME="py${PY_VERSION//./}"   # py312, py311, ...
CONDA_PREFIX="/opt/conda"        # Miniforge location
CONDA_ENVS_DIR="/opt/conda-envs" # shared envs root
CONDA_PKGS_DIR="/opt/conda-pkgs" # shared conda package cache
PIP_CACHE_DIR="/opt/pip-cache"   # shared pip cache
ENV_PATH="${CONDA_ENVS_DIR}/${ENV_NAME}"
STABLE_PY_LINK="/opt/python"     # stable, version-agnostic symlink
PROFILE_FILE="/etc/profile.d/99-custom--profile.sh"   # THIS HAS TO CHANGE

# Make sure conda & caches see these directories even during this script
export CONDA_PKGS_DIRS="$CONDA_PKGS_DIR"
export CONDA_ENVS_DIRS="$CONDA_ENVS_DIR"

# ---- helpers ----
enforce_shared_perms() {
  # Create shared dirs & make them sticky tmp-style (1777)
  mkdir -p "$CONDA_ENVS_DIR" "$CONDA_PKGS_DIR" "$PIP_CACHE_DIR"
  chmod 1777 "$CONDA_ENVS_DIR" "$CONDA_PKGS_DIR" "$PIP_CACHE_DIR"

  # Also ensure the default pkgs dir under the prefix is writable if used
  mkdir -p "${CONDA_PREFIX}/pkgs"
  chmod 1777 "${CONDA_PREFIX}/pkgs"
}

# ---- base tools ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl bzip2 ca-certificates tini
rm -rf /var/lib/apt/lists/*

mkdir -p "$CONDA_PREFIX"
chmod 0755 "$CONDA_PREFIX"

# Apply perms once before install
enforce_shared_perms

# ---- detect arch for Miniforge ----
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)         MARCH="x86_64" ;;
  aarch64|arm64)  MARCH="aarch64" ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 2 ;;
esac

# ---- install or reuse Miniforge (handles empty /opt/conda) ----
if [ -x "${CONDA_PREFIX}/bin/conda" ]; then
  echo "ℹ️  Found existing conda at ${CONDA_PREFIX} — reusing."
else
  echo "⬇️  Downloading Miniforge for ${MARCH}..."
  curl -fsSL -o /tmp/miniforge.sh \
    "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${MARCH}.sh"

  # If target dir exists (even empty), use -u to allow in-place install/update.
  INSTALL_FLAGS="-b -p ${CONDA_PREFIX}"
  [ -d "${CONDA_PREFIX}" ] && INSTALL_FLAGS="-b -u -p ${CONDA_PREFIX}"

  bash /tmp/miniforge.sh ${INSTALL_FLAGS}
  rm -f /tmp/miniforge.sh
fi

# Re-apply perms in case installer changed anything
enforce_shared_perms

CONDA_BIN="${CONDA_PREFIX}/bin/conda"

# ---- conservative, idempotent conda config (no list keys) ----
"${CONDA_BIN}" config --system --set channel_priority strict
"${CONDA_BIN}" config --system --add channels conda-forge || true
"${CONDA_BIN}" config --system --set auto_update_conda false
"${CONDA_BIN}" config --system --set always_yes true

# ---- create the env at a fixed path (idempotent) ----
if [ -d "${ENV_PATH}" ]; then
  echo "ℹ️  Env '${ENV_NAME}' already exists at ${ENV_PATH} — skipping creation."
else
  echo "🛠️  Creating Conda env '${ENV_NAME}' at ${ENV_PATH} with Python ${PY_VERSION} ..."
  "${CONDA_BIN}" create -p "${ENV_PATH}" "python=${PY_VERSION}" pip
fi

# ---- stable symlink for tools that want a fixed location ----
ln -snf "$ENV_PATH" "$STABLE_PY_LINK"

# Optional convenience shims (do NOT fail if missing)
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python || true
ln -sfn "${STABLE_PY_LINK}/bin/pip"    /usr/local/bin/pip    || true

# ---- system-wide shell defaults for any future user/session ----
cat >"$PROFILE_FILE" <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export CONDA_PREFIX="/opt/conda"

# Ensure conda CLI is on PATH even if conda.sh isn’t sourced yet
if [ -d "${CONDA_PREFIX}/bin" ]; then
  case ":$PATH:" in *":${CONDA_PREFIX}/bin:"*) : ;; *)
    export PATH="${CONDA_PREFIX}/bin:${PATH}"
  esac
fi

# Expose 'conda' in interactive shells
if [ -f "${CONDA_PREFIX}/etc/profile.d/conda--profile.sh"" ]; then
  . "${CONDA_PREFIX}/etc/profile.d/conda--profile.sh""
fi

# Shared caches/dirs
export CONDA_ENVS_DIRS="/opt/conda-envs"
export CONDA_PKGS_DIRS="/opt/conda-pkgs"
export PIP_CACHE_DIR="/opt/pip-cache"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1

# Stable Python location for tools and PATH
export PY_STABLE="/opt/python"
if [ -d "${PY_STABLE}/bin" ]; then
  case ":$PATH:" in
    *":${PY_STABLE}/bin:"*) : ;;
    *) export PATH="${PY_STABLE}/bin:${PATH}" ;;
  esac
fi

# Don't auto-activate base; users can `conda activate <env>` explicitly
export CONDA_AUTO_ACTIVATE_BASE=false
# ---- end defaults ----
EOF
chmod 0644 "$PROFILE_FILE"

# ---- friendly summary ----
"${CONDA_PREFIX}/bin/conda" --version || true
"${STABLE_PY_LINK}/bin/python" -V || true
echo "✅ Conda present at ${CONDA_PREFIX}"
echo "✅ Shared envs root at ${CONDA_ENVS_DIR}, pkgs cache at ${CONDA_PKGS_DIR} (sticky & world-writable)"
echo "✅ Env '${ENV_NAME}' at ${ENV_PATH}"
echo "✅ Stable Python symlink at ${STABLE_PY_LINK} (and shims to /usr/local/bin/python & pip)"
echo "✅ ${PROFILE_FILE} adds /opt/conda/bin to PATH and exposes conda in new shells"

echo
echo "Use it now in this shell:"
echo "  export PATH=\"/opt/conda/bin:\$PATH\" && . /opt/conda/etc/profile.d/conda--profile.sh"
echo
