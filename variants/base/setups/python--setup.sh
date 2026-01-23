#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root


PROFILE_FILE="/etc/profile.d/53-cb-python--profile.sh"  # profile to be run when login

# ---- validate python version format ----
# accepts X.Y or X.Y.Z (exact patch recommended)
PY_VERSION=${1:-3.12}
CB_PY_VERSION=${PY_VERSION}
if [[ ! "$CB_PY_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "❌ Invalid Python version format: '$CB_PY_VERSION'"
  echo "   Expected format: X.Y or X.Y.Z (e.g., 3.11 or 3.11.6)"
  exit 1
fi

PY_SERIES="$(echo "${CB_PY_VERSION}" | cut -d. -f1-2)"

# ---- variables ----
CB_PYENV_ROOT="/opt/pyenv"                        # system-wide pyenv
CB_VENV_ROOT="/opt/venvs"                         # shared venvs root
CB_VENV_DIR="${CB_VENV_ROOT}/py${CB_PY_VERSION}"  # venv directory

STABLE_PY_LINK="/opt/python"    # stable, version-agnostic symlink
PIP_CACHE_DIR="/opt/pip-cache"  # shared pip cache

# System-wide location to host UV-installed pythons (mirrored out of /root, etc.)
UV_PYTHONS_DIR="/opt/local-pythons"

# Thin wrappers to ensure "pip" always uses the selected python (avoid confusion w/ apt)
PIP_WRAPPER="/usr/local/bin/pip"
PIP3_WRAPPER="/usr/local/bin/pip3"

export DEBIAN_FRONTEND=noninteractive

# ---- dirs & shared perms ----
mkdir -p   "$CB_PYENV_ROOT" "$CB_VENV_ROOT" "$PIP_CACHE_DIR" "$UV_PYTHONS_DIR"
chmod 0755 "$CB_PYENV_ROOT"
chmod 0755 "$UV_PYTHONS_DIR"
chmod 1777 "$CB_VENV_ROOT" "$PIP_CACHE_DIR"

# ---- install or reuse pyenv (idempotent) ----
if [ -x "${CB_PYENV_ROOT}/bin/pyenv" ]; then
  echo "ℹ️  Found existing pyenv at ${CB_PYENV_ROOT} — reusing."
else
  echo "⬇️  Installing pyenv to ${CB_PYENV_ROOT} ..."
  git clone --depth 1 https://github.com/pyenv/pyenv.git "$CB_PYENV_ROOT"
fi

# Make pyenv available in this shell
export CB_PYENV_ROOT
export PATH="$CB_PYENV_ROOT/bin:$PATH"
eval "$("$CB_PYENV_ROOT/bin/pyenv" init -)"

# ---- install uv (fast prebuilt CPython manager) ----
if ! command -v uv >/dev/null 2>&1; then
  echo "⬇️  Installing uv (prebuilt Python manager) ..."
  INSTALL_DIR="/usr/local/uv"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$INSTALL_DIR" sh

  # Add uv to PATH (handles both $INSTALL_DIR and $INSTALL_DIR/bin layouts)
  if [ -x "$INSTALL_DIR/uv" ]; then
    export PATH="$INSTALL_DIR:$PATH"
  elif [ -x "$INSTALL_DIR/bin/uv" ]; then
    export PATH="$INSTALL_DIR/bin:$PATH"
  fi
  hash -r 2>/dev/null || true
fi
command -v uv >/dev/null 2>&1 || { echo "❌ uv not on PATH"; exit 1; }
chmod -R a+rX /usr/local/uv

# ---- resolve exact patch if only X.Y was given (NO --resolve) ----
if [[ "$CB_PY_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "🔎 Installing latest patch for $CB_PY_VERSION via uv and detecting exact version ..."
  uv python install "$CB_PY_VERSION" >/dev/null
  UV_PY_BIN="$(uv python find "$CB_PY_VERSION" || true)"
  [ -n "${UV_PY_BIN}" ] || { echo "❌ uv could not find installed Python $CB_PY_VERSION"; exit 1; }
  # If we accidentally got a project venv, we’ll fix it in the guard below.
  CB_PY_VERSION="$("$UV_PY_BIN" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || echo "$CB_PY_VERSION")"
fi

# ---- ensure prebuilt CPython $CB_PY_VERSION is available via uv ----
echo "⚡ Ensuring prebuilt CPython $CB_PY_VERSION is available ..."
_unused="$(uv python install "$CB_PY_VERSION" >/dev/null || true)"
UV_PY_BIN="$(uv python find "$CB_PY_VERSION")"
[ -n "$UV_PY_BIN" ] || { echo "❌ uv could not find installed Python $CB_PY_VERSION"; exit 1; }

# ---- GUARD: reject project venv paths (…/.venv/…) ----
if [[ "$UV_PY_BIN" =~ /(\.venv|venv|\.env)[^/]*/bin/ ]]; then
  echo "⚠️  uv returned a project venv interpreter: $UV_PY_BIN"
  echo "    Forcing a clean UV-managed interpreter..."
  uv python install "$CB_PY_VERSION" >/dev/null
  UV_PY_BIN="$(uv python find "$CB_PY_VERSION")"
  [[ ! "$UV_PY_BIN" =~ /(\.venv|venv|\.env)[^/]*/bin/ ]] || {
    echo "❌ still pointing to a venv; aborting to avoid copying a broken tree"; exit 1; }
fi

UV_PREFIX="$(dirname "$(dirname "$UV_PY_BIN")")"
PY_EXE="$UV_PREFIX/bin/python"
[ -x "$PY_EXE" ] || PY_EXE="$UV_PREFIX/bin/python3"
[ -x "$PY_EXE" ] || { echo "❌ expected python or python3 in $UV_PREFIX/bin"; exit 1; }

# ---- sanity-check that we're mirroring a real Python prefix (not /usr) ----
case "$UV_PREFIX" in
  /usr|/usr/local|"")
    echo "❌ Refusing to mirror system prefix: $UV_PREFIX"
    exit 1
    ;;
esac

# Expect a CPython-like layout (bin/python and lib/pythonX.Y)
if [ ! -x "$UV_PREFIX/bin/python" ] && [ ! -x "$UV_PREFIX/bin/python3" ]; then
  echo "❌ $UV_PREFIX does not contain a Python binary under bin/"
  exit 1
fi
if [ ! -d "$UV_PREFIX/lib/python${PY_SERIES}" ]; then
  echo "❌ $UV_PREFIX missing expected lib/python${PY_SERIES} tree; refusing to mirror"
  exit 1
fi

# ---- COPY uv interpreter out of /root into world-readable location ----
# Mirror interpreter tree into /opt/local-pythons/$CB_PY_VERSION and link pyenv to it.
DEST_PREFIX="${UV_PYTHONS_DIR}/${CB_PY_VERSION}"
if [ -x "${DEST_PREFIX}/bin/python" ]; then
  echo "ℹ️  Using existing system Python at ${DEST_PREFIX}."
else
  echo "📦  Copying Python $CB_PY_VERSION from ${UV_PREFIX} to ${DEST_PREFIX} ..."
  mkdir -p      "${DEST_PREFIX}"
  cp    -RPp    "${UV_PREFIX}/." "$DEST_PREFIX/"
  chmod -R a+rX "${DEST_PREFIX}"
fi

# ---- register this interpreter inside pyenv (no build) ----
mkdir -p "$CB_PYENV_ROOT/versions"
ln -snf "$DEST_PREFIX" "$CB_PYENV_ROOT/versions/$CB_PY_VERSION"

PY_PREFIX="$(PYENV_ROOT="$CB_PYENV_ROOT" "$CB_PYENV_ROOT/bin/pyenv" prefix "$CB_PY_VERSION")"
[ -x "$PY_PREFIX/bin/python" ] || { echo "❌ pyenv prefix invalid"; exit 1; }

# ---- create venv at a fixed path using uv (avoid ensurepip issues) ----
# Use full patch in the directory name: /opt/venvs/py3.12.11
ENV_NAME="py${CB_PY_VERSION}"            # e.g. py3.12.11
ENV_PATH="${CB_VENV_ROOT}/${ENV_NAME}"

if [ -d "${ENV_PATH}" ]; then
  echo "ℹ️  Venv '${ENV_NAME}' already exists at ${ENV_PATH} — skipping creation."
else
  echo "🧪  Creating venv '${ENV_NAME}' at ${ENV_PATH} using uv ..."
  UV_PY_EXE="${DEST_PREFIX}/bin/python"
  [ -x "$UV_PY_EXE" ] || { echo "❌ expected $UV_PY_EXE"; exit 1; }

  # Create the venv
  uv venv --python "$UV_PY_EXE" "${ENV_PATH}"

  # ✅ Ensure classic pip/setuptools/wheel exist inside the venv
  # (some tooling calls 'pip' directly; uv alone won't provide that console script)
  uv pip install --python "${ENV_PATH}/bin/python" --upgrade pip setuptools wheel
fi
chmod -R 0777 "${ENV_PATH}"

# maintain a series convenience symlink (e.g., py3.12 -> py3.12.11)
ln -sfn "${ENV_PATH}" "${CB_VENV_ROOT}/py${PY_SERIES}"

# ---- stable symlink & convenience shims ----
ln -snf "$ENV_PATH" "$STABLE_PY_LINK"

# Prefer stable venv for python/python3 via /usr/local/bin (PATH usually picks this before /usr/bin)
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python  || true
ln -sfn "${STABLE_PY_LINK}/bin/python" /usr/local/bin/python3 || true

# Thin wrappers: ensure "pip" always means "python -m pip" for the stable venv
cat >"$PIP_WRAPPER" <<'EOF'
#!/bin/sh
set -eu
exec /opt/python/bin/python -m pip "$@"
EOF
chmod 0755 "$PIP_WRAPPER"

cat >"$PIP3_WRAPPER" <<'EOF'
#!/bin/sh
set -eu
exec /opt/python/bin/python -m pip "$@"
EOF
chmod 0755 "$PIP3_WRAPPER"

# refresh command lookup cache in case this shell keeps running more commands
hash -r || true

# ---- system-wide shell defaults (last install wins) ----
cat >"$PROFILE_FILE" <<'EOF'
# Stable Python (managed by python--setup.sh)
export CB_PYENV_ROOT="/opt/pyenv"
export CB_PY_STABLE="/opt/python"
export CB_VENV_ROOT="/opt/venvs"
export PIP_CACHE_DIR="/opt/pip-cache"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1

# Avoid env vars that can break venv resolution
unset PYTHONHOME

# Make the stable venv "the" python by default for shells:
export VIRTUAL_ENV="/opt/python"

# Put /opt/python/bin first exactly once
case ":$PATH:" in
  *":${CB_PY_STABLE}/bin:"*) ;;
  *) PATH="${CB_PY_STABLE}/bin:${PATH}" ;;
esac

# Put /usr/local/bin early (thin pip wrappers + python shims live here)
case ":$PATH:" in
  *":/usr/local/bin:"*) ;;
  *) PATH="/usr/local/bin:${PATH}" ;;
esac

# Ensure pyenv shims are on PATH (once)
case ":$PATH:" in
  *":${CB_PYENV_ROOT}/bin:"*) ;;
  *) PATH="${CB_PYENV_ROOT}/bin:${PATH}" ;;
esac

# Ensure uv is on PATH (once) — supports both layouts: /usr/local/uv and /usr/local/uv/bin
case ":$PATH:" in
  *":/usr/local/uv/bin:"*|*":/usr/local/uv:"*) ;;
  *) PATH="/usr/local/uv/bin:/usr/local/uv:${PATH}" ;;
esac

# Auto-select the series venv that matches /opt/python (managed by python--setup.sh)

# 1) Resolve active version from the stable symlink
if [ -x /opt/python/bin/python ]; then
  CB_PY_VERSION="$(/opt/python/bin/python -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || true)"
else
  CB_PY_VERSION=""
fi
export CB_PY_VERSION
export CB_VENV_DIR="/opt/venvs/py${CB_PY_VERSION}"

# 2) Compute the series (X.Y) from CB_PY_VERSION (POSIX-safe)
# Examples: 3.12.11 -> 3.12 ; 3.12 -> 3.12 ; 3 -> ""
case "${CB_PY_VERSION}" in
  *.*.*) CB_PY_SERIES="${CB_PY_VERSION%.*}" ;;  # strip patch only
  *.*)   CB_PY_SERIES="${CB_PY_VERSION}"    ;;  # already X.Y form
  *)     CB_PY_SERIES="" ;;
esac
export CB_PY_SERIES

# 3) Choose the series venv dir if available, else fall back to /opt/python
export CB_VENV_SERIES_DIR="/opt/venvs/py${CB_PY_SERIES}"

# 4) Put the chosen interpreter FIRST on PATH (exactly once)
#    Strip any other /opt/venvs/py*/bin entries to avoid confusion.
if [ -n "$CB_VENV_SERIES_DIR" ] && [ -d "${CB_VENV_SERIES_DIR}/bin" ]; then
  CLEAN_PATH="$(printf '%s' "$PATH" \
    | awk -v RS=: -v ORS=: '!/^[[:space:]]*$/{print}' \
    | sed -E 's#(^|:)/opt/venvs/py[0-9]+\.[0-9]+(\.[0-9]+)?/bin(:|$)#\1#g; s#::#:#g; s#^:|:$##g')"

  case ":$CLEAN_PATH:" in
    *":${CB_VENV_SERIES_DIR}/bin:"*) PATH="$CLEAN_PATH" ;;
    *) PATH="${CB_VENV_SERIES_DIR}/bin:${CLEAN_PATH}" ;;
  esac
  export PATH
fi

# ---- python_setup_info helper ----
python_setup_info() {
  set -o pipefail
  _hdr() { printf "\n\033[1m%s\033[0m\n" "$*"; }

  _hdr "Python setup summary"
  printf "CB_PYENV_ROOT=%s\n"        "$CB_PYENV_ROOT"
  printf "CB_PY_STABLE=%s\n"         "$CB_PY_STABLE"
  printf "CB_VENV_ROOT=%s\n"         "$CB_VENV_ROOT"
  printf "CB_PY_VERSION=%s\n"        "$CB_PY_VERSION"
  printf "CB_PY_SERIES=%s\n"         "$CB_PY_SERIES"
  printf "CB_VENV_SERIES_DIR=%s\n"   "$CB_VENV_SERIES_DIR"
  printf "VIRTUAL_ENV=%s\n"          "${VIRTUAL_ENV:-}"
  printf "python=%s\n"               "$(command -v python 2>/dev/null || true)"
  printf "python3=%s\n"              "$(command -v python3 2>/dev/null || true)"
  printf "pip=%s\n"                  "$(command -v pip 2>/dev/null || true)"
}

# #== Override what venv activation does ==
# Bash
export PS1="\[\e[1;32m\]${CB_CONTAINER_NAME:-booth}\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ "
# Zsh
export PROMPT="%%B%%F{green}${CB_CONTAINER_NAME:-booth}%%b%%f:%%B%%F{blue}%%~%%b%%f❯ "

alias python-setup-info='python_setup_info'
EOF
chmod 0644 "$PROFILE_FILE"

ensure_env() {
  key="$1"; val="$2"
  if grep -qE "^${key}=" /etc/environment 2>/dev/null; then
    sed -i -E "s|^${key}=.*$|${key}=${val}|" /etc/environment
  else
    echo "${key}=${val}" >> /etc/environment
  fi
}

ensure_env CB_PYENV_ROOT                 /opt/pyenv
ensure_env PY_STABLE                     /opt/python
ensure_env CB_VENV_ROOT                  /opt/venvs
ensure_env PIP_CACHE_DIR                 /opt/pip-cache
ensure_env PIP_DISABLE_PIP_VERSION_CHECK 1
ensure_env PYTHONUNBUFFERED              1
ensure_env VIRTUAL_ENV                   /opt/python

# ---- summary ----
ACTIVE_VER="$("${STABLE_PY_LINK}/bin/python" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || true)"
"${STABLE_PY_LINK}/bin/python" -V || true
"${STABLE_PY_LINK}/bin/python" -m pip --version || true
echo "✅ pyenv at ${CB_PYENV_ROOT}"
echo "✅ Python ${CB_PY_VERSION} mirrored at ${DEST_PREFIX} and registered under pyenv at ${PY_PREFIX}"
echo "✅ Venv '${ENV_NAME}' at ${ENV_PATH}"
echo "✅ Stable Python symlink at ${STABLE_PY_LINK} → $(readlink -f "${STABLE_PY_LINK}")"
echo "✅ ${PROFILE_FILE} sets VIRTUAL_ENV=/opt/python and puts /opt/python/bin first on PATH (for shells)"
echo "✅ pip/pip3 wrappers installed at /usr/local/bin to force 'python -m pip' (stable venv)"
echo "✅ ACTIVE_VER detected now: ${ACTIVE_VER}"
echo
echo "Verify (in any shell):"
echo "  which python3 && python3 -V"
echo "  python3 -c 'import sys; print(sys.executable); print(sys.base_prefix); print(sys.prefix)'"
echo "  pip --version"
