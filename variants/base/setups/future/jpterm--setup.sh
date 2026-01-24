#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# jpterm--setup.sh
# Installs jpterm (Jupyter Terminal) for running notebooks in the terminal.
#
# jpterm allows running Jupyter notebooks without a browser - great for:
# - Executable documentation (especially with bash kernel)
# - Headless/SSH environments
# - Quick notebook execution
#
# Prereqs:
#   - python--setup.sh already ran (Python 3.12+ required)
#   - /etc/profile.d/53-cb-python--profile.sh should be sourced
# -----------------------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---- Root check ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

# ---- Load Python environment ----
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# ---- Version check ----
REQUIRED_VERSION="3.12"

if ! command -v python &>/dev/null; then
  echo "❌ Python is not installed. Run python--setup.sh first."
  exit 1
fi

PY_VERSION="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PY_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
  echo "❌ Python $REQUIRED_VERSION or newer is required. You have Python $PY_VERSION."
  echo "   Run: python--setup.sh $REQUIRED_VERSION"
  exit 1
fi

# ---- Idempotent check ----
if command -v jpterm &>/dev/null; then
  echo "✅ jpterm already installed: $(command -v jpterm)"
  exit 0
fi

# ---- Install jpterm via pipx ----
echo "📦 Installing jpterm (Jupyter Terminal)..."

export PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}"
export PIP_DISABLE_PIP_VERSION_CHECK=1

# Ensure pipx is available
python -m pip install -U pipx >/dev/null
python -m pipx ensurepath >/dev/null

# Install jpterm
python -m pipx install jpterm

# Install jupyter_client and bash_kernel for notebook execution
echo "📦 Installing jupyter_client and bash_kernel..."
python -m pip install -U jupyter_client bash_kernel >/dev/null
python -m bash_kernel.install >/dev/null

# ---- Ensure jpterm is on PATH for all users ----
# pipx installs to ~/.local/bin by default, link to /usr/local/bin
PIPX_BIN="${HOME}/.local/bin/jpterm"
if [ -x "$PIPX_BIN" ] && [ ! -e /usr/local/bin/jpterm ]; then
  ln -sf "$PIPX_BIN" /usr/local/bin/jpterm
fi

# ---- Verification ----
if command -v jpterm &>/dev/null; then
  echo "✅ jpterm installed: $(command -v jpterm)"
else
  echo "⚠️  jpterm installed but not on PATH. Add ~/.local/bin to PATH."
fi

echo "✅ jupyter_client and bash_kernel installed"
echo
echo "Usage:"
echo "  jpterm notebook.ipynb    # Run a notebook in terminal"
echo "  nbook notebook.ipynb     # Alias (if profile loaded)"
