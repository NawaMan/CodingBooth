#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest Aider
  $0 --version 0.82.3        # pin specific version

Notes:
- Installs Aider into an isolated venv at /opt/aider
- Symlinks aider to /usr/local/bin/aider
- Requires python3 (will install via apt if missing)
- Aider supports Python 3.10-3.12 only. When the system python3 is outside
  that range (Ubuntu 26.04 ships 3.14), a uv-managed Python 3.12 is
  downloaded into /opt/aider-python for Aider alone; the system Python is
  left as it is
- Uses API keys from environment (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- ensure python3 ----
export DEBIAN_FRONTEND=noninteractive
if ! command -v python3 &>/dev/null; then
  echo "📦 Installing python3 ..."
  apt-get update
  apt-get install -y --no-install-recommends python3 python3-pip python3-venv
  rm -rf /var/lib/apt/lists/*
else
  # Ensure venv module is available
  if ! python3 -m venv --help &>/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends python3-venv
    rm -rf /var/lib/apt/lists/*
  fi
fi

# ---- create venv and install ----
VENV_DIR="/opt/aider"
if [[ "$REQ_VER" == "latest" ]]; then
  AIDER_SPEC="aider-chat"
else
  AIDER_SPEC="aider-chat==${REQ_VER}"
fi

# Aider declares requires-python >=3.10,<3.13. On a newer Python, pip finds no
# current release, backtracks through old ones and crashes in its resolver. So
# the system python3 is used only when Aider supports it; otherwise Aider gets
# a uv-managed Python 3.12 of its own -- what Aider's own installer
# (aider-install) does. It lives in /opt/aider-python, beside the venv rather
# than in it, and readable by every user.
AIDER_PYTHON="3.12"
AIDER_PYTHON_DIR="/opt/aider-python"
if python3 -c 'import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] < (3, 13) else 1)'; then
  echo "🛠  Creating venv at ${VENV_DIR} with $(python3 --version) ..."
  python3 -m venv "$VENV_DIR"
  echo "⬇️  Installing ${AIDER_SPEC} ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir "$AIDER_SPEC"
else
  echo "ℹ️  $(python3 --version) is outside what Aider supports (3.10-3.12); giving it its own Python ${AIDER_PYTHON}."
  BOOTSTRAP="$(mktemp -d)"
  trap 'rm -rf "$BOOTSTRAP"' EXIT
  python3 -m venv "$BOOTSTRAP/venv"
  "$BOOTSTRAP/venv/bin/pip" install --no-cache-dir --quiet uv
  UV="$BOOTSTRAP/venv/bin/uv"
  export UV_PYTHON_INSTALL_DIR="$AIDER_PYTHON_DIR" UV_CACHE_DIR="$BOOTSTRAP/cache"
  rm -rf "$VENV_DIR"
  echo "🛠  Creating venv at ${VENV_DIR} with a uv-managed Python ${AIDER_PYTHON} (in ${AIDER_PYTHON_DIR}) ..."
  "$UV" venv --seed --python "$AIDER_PYTHON" --python-preference only-managed "$VENV_DIR"
  echo "⬇️  Installing ${AIDER_SPEC} ..."
  "$UV" pip install --python "$VENV_DIR/bin/python" "$AIDER_SPEC"
  chmod -R a+rX "$AIDER_PYTHON_DIR" "$VENV_DIR"
fi

# ---- symlink binary ----
echo "🔗 Creating symlink in /usr/local/bin ..."
ln -sf "$VENV_DIR/bin/aider" /usr/local/bin/aider

# ---- friendly summary ----
echo "✅ Aider installed."
echo -n "   aider → "; aider --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Try: aider --version
- Start coding: aider

Notes:
- Aider is installed in an isolated venv at /opt/aider (on /opt/aider-python's
  Python 3.12 when the system Python is too new for it).
- Configure API keys via environment variables:
    OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.
- See: https://aider.chat/
EON
