#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# codeserver--setup.sh
# Installs code-server + Jupyter (Python venv). Bash kernel is installed via external script.
# Auth behavior:
#   - If PASSWORD is empty or unset -> auth: none (no password)
#   - If PASSWORD is set           -> auth: password (value = PASSWORD)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# This is to be run by sudo
# Ensure script is run as root (EUID == 0)
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi


PROFILE_FILE="/etc/profile.d/55-cb-codeserver--profile.sh"
STARTER_FILE=/usr/local/bin/codeserver


# Load python env exported by the base setup
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# Extensions
CODESERVER_EXTENSION_DIR=/usr/local/share/code-server/extensions

# Overridable PASSWORD
PASSWORD="${PASSWORD:-}"  # empty => no password


echo "[1/9] Install code-server…"
if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi
command -v code-server >/dev/null


echo "[2/9] Pre-seed Jupyter into ${CB_VENV_DIR} (build-time)…"

# Always use the workspace venv Python, not whatever "python" happens to be.
VENV_PY="${CB_VENV_DIR}/bin/python"
if [ ! -x "$VENV_PY" ]; then
  echo "❌ Expected venv python at ${CB_VENV_DIR} but it is missing or not executable"
  exit 1
fi

# Upgrade basics in the venv
env PIP_CACHE_DIR="${PIP_CACHE_DIR}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "$VENV_PY" -m pip install -U pip setuptools wheel

# Install Jupyter + ipykernel into the venv
env PIP_CACHE_DIR="${PIP_CACHE_DIR}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "$VENV_PY" -m pip install -U jupyter ipykernel

# Kernelspec (use actual patch version for display), bound to this venv
ACTUAL_VER="$("$VENV_PY" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"
"$VENV_PY"             \
  -m ipykernel install \
  --sys-prefix         \
  --name=python3       \
  --display-name="Python ${ACTUAL_VER} (venv)"


cat >> "$PROFILE_FILE" <<'SH'
# codeserver setup inspector
# Usage: codeserver-setup-info
codeserver_setup_info() {
  set -o pipefail
  _hdr() { printf "\n\033[1m%s\033[0m\n" "$*"; }
  _ok()  { printf "✅ %s\n" "$*"; }
  _warn(){ printf "⚠️  %s\n" "$*"; }
  _err() { printf "❌ %s\n" "$*"; }

  # Defaults that match your setup
  local csuser="${CSUSER:-coder}"
  local cshome="${CSHOME:-/home/$csuser}"
  local config_file="${CONFIG_FILE:-$cshome/.config/code-server/config.yaml}"
  local ext_dir="${CODESERVER_EXTENSION_DIR:-/usr/local/share/code-server/extensions}"
  local launcher="${LAUNCHER:-/usr/local/bin/codeserver}"

  _hdr "code-server"
  if command -v code-server >/dev/null 2>&1; then
    _ok "Binary: $(command -v code-server)"
    _ok "Version: $(code-server --version 2>/dev/null | head -n1)"
  else
    _err "code-server not found on PATH"
  fi
  [ -x "$launcher" ] && _ok "Launcher: $launcher"

  _hdr "Python / venv"
  local venv="${CB_VENV_DIR:-${VENV_SERIES_DIR:-/opt/venvs/py${CB_PY_SERIES:-}}}"
  if [ -n "$venv" ] && [ -x "$venv/bin/python" ]; then
    _ok "CB_VENV_DIR: $venv"
    _ok "Python: $("$venv/bin/python" -V 2>&1)"
  elif [ -x /opt/python/bin/python ]; then
    _warn "CB_VENV_DIR not set; using /opt/python"
    _ok "Python: $(/opt/python/bin/python -V 2>&1)"
  else
    _err "No Python interpreter found"
  fi

  _hdr "Jupyter"
  local jbin=""
  if [ -n "$venv" ] && [ -x "$venv/bin/jupyter" ]; then
    jbin="$venv/bin/jupyter"
  elif command -v jupyter >/dev/null 2>&1; then
    jbin="$(command -v jupyter)"
  fi
  if [ -n "$jbin" ]; then
    _ok "jupyter: $("$jbin" --version 2>/dev/null | head -n1)"
    "$jbin" kernelspec list 2>/dev/null | sed 's/^/  /'
  else
    _warn "jupyter not found"
  fi

  _hdr "Extensions"
  if [ -d "$ext_dir" ]; then
    local n
    n="$(find "$ext_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    _ok "Shared dir: $ext_dir (count: $n)"
    find "$ext_dir" -mindepth 1 -maxdepth 1 -type d -printf "  - %f\n" 2>/dev/null | sort | head -n 20
  else
    _warn "Extensions dir not found: $ext_dir"
  fi

  _hdr "Auth config"
  if [ -f "$config_file" ]; then
    local auth pass_set
    auth="$(grep -E '^[[:space:]]*auth:' "$config_file" | awk '{print $2}' | tr -d '\r' || true)"
    grep -Eq '^[[:space:]]*password:' "$config_file" && pass_set=yes || pass_set=no
    _ok "Config: $config_file"
    _ok "Auth: ${auth:-unknown}  Password set: $pass_set"
  else
    _warn "Config not found: $config_file"
  fi

  _hdr "Quick start"
  echo "  codeserver 10000   # start on port 10000 (uses current \$PASSWORD if set)"
}
alias codeserver-setup-info='codeserver_setup_info'
SH
chmod 0644 "$PROFILE_FILE"

# Make it available in THIS shell immediately:
source "$PROFILE_FILE" || true


# Make it usable right away in THIS shell
source "${CB_VENV_DIR}/bin/activate"


# 1) Create a shared directory
mkdir -p        "$CODESERVER_EXTENSION_DIR"
chown root:root "$CODESERVER_EXTENSION_DIR"
chmod 1777 -Rf  "$CODESERVER_EXTENSION_DIR"     # root-writable, others read/exec (matches your comment)

# 2) Move what you already installed as root and link it back
ROOT_CODESERVER_EXTENSION_DIR=/root/.local/share/code-server/extensions
if [ -d "$ROOT_CODESERVER_EXTENSION_DIR" ]; then
  mkdir -p "$CODESERVER_EXTENSION_DIR"
  cp -a "$ROOT_CODESERVER_EXTENSION_DIR"/. "$CODESERVER_EXTENSION_DIR"/
  rm -Rf "$ROOT_CODESERVER_EXTENSION_DIR"
fi

# Make the link exact (no trailing slashes; -T to treat LINKNAME as a file)
mkdir -p    "$ROOT_CODESERVER_EXTENSION_DIR"
rm    -Rf   "$ROOT_CODESERVER_EXTENSION_DIR"
ln    -sfnT "$CODESERVER_EXTENSION_DIR" "$ROOT_CODESERVER_EXTENSION_DIR"

if [ -f /usr/local/share/code-server/extensions/extensions.json ]; then
  chmod 777 /usr/local/share/code-server/extensions/extensions.json
else
  echo "[]" > /usr/local/share/code-server/extensions/extensions.json
  chmod 777 /usr/local/share/code-server/extensions/extensions.json
fi

# 3) Install future extensions into the shared dir
code-server --extensions-dir "$CODESERVER_EXTENSION_DIR" \
  --install-extension ms-toolsai.jupyter \
  --install-extension ms-python.python

# Extensions now in $CODESERVER_EXTENSION_DIR
code-server --extensions-dir "$CODESERVER_EXTENSION_DIR" --list-extensions || true


echo "[4/9] Create launcher: /usr/local/bin/codeserver"
export CODESERVER_EXTENSION_DIR
envsubst '$PASSWORD $CODESERVER_EXTENSION_DIR' > ${STARTER_FILE} <<'LAUNCH'
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

PORT=${1:-10000}

# Ensure PATH and /opt/python are active in non-login shells
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# ==== Runtime tunables ====
# Make venv kernels visible to any Jupyter process
export JUPYTER_PATH="${CB_VENV_DIR}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter${JUPYTER_PATH:+:$JUPYTER_PATH}"

# Use the current user's home directory
CSHOME="${HOME}"

# Pre-create config dirs for this user
mkdir -p "$CSHOME/.config" "$CSHOME/.local/share/code-server" "$CSHOME/.local/share/code-server/User"

# Write code-server config for this user (auth decided at generation time via envsubst)
mkdir -p "${CSHOME}/.config/code-server"
CONFIG_FILE="${CSHOME}/.config/code-server/config.yaml"

AUTH=$( [ -z "$PASSWORD" ] && echo none || echo password )
PASS_LINE=$( [ "$AUTH" = "password" ] && echo "password: $PASSWORD" || echo "" )

cat >"$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:$PORT
cert: false
auth: ${AUTH}
${PASS_LINE}
EOF

# Settings
SETTING_DIR=$CSHOME/.local/share/code-server/User
SETTINGS_JSON="$SETTING_DIR/settings.json"
mkdir -p "$SETTING_DIR"

cat > "$SETTINGS_JSON" <<JSON
{
  "python.defaultInterpreterPath": "${CB_VENV_DIR}/bin/python",
  "jupyter.jupyterServerType": "local",

  "terminal.integrated.profiles.linux": {
    "bash-login": { "path": "/bin/bash", "args": ["-l"] }
  },
  "terminal.integrated.defaultProfile.linux": "bash-login",
  "python.terminal.activateEnvironment": true,
  "workbench.colorTheme": "Default Dark+",
  "editor.fontSize": 14
}
JSON

# -------- default shell for everything code-server launches (incl. Jupyter ext) --------
DEFAULT_SHELL="/bin/bash"

echo "Starting code-server. This may take sometime ..."

# Ensure these vars are present in the code-server process environment
SHELL="$DEFAULT_SHELL" \
PASSWORD="$PASSWORD" \
JUPYTER_PATH="$JUPYTER_PATH" \
exec code-server \
    --extensions-dir "$CODESERVER_EXTENSION_DIR" \
    --bind-addr      "0.0.0.0:$PORT"             \
    --auth           "$AUTH"                     \
    "$CSHOME/code"

LAUNCH
chmod 755 ${STARTER_FILE}


cat <<EOF

✅ Setup complete.

Start:
  ${STARTER_FILE}

Auth mode:
  $( [[ -z "$PASSWORD" ]] && echo "No password (auth: none)" || echo "Password set (auth: password)" )

Kernels available (scoped to venv):
  - Python 3 (venv)
  - Bash
EOF
