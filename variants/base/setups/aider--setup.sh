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
echo "🛠  Creating venv at ${VENV_DIR} ..."
python3 -m venv "$VENV_DIR"

if [[ "$REQ_VER" == "latest" ]]; then
  echo "⬇️  Installing latest Aider ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir aider-chat
else
  echo "⬇️  Installing Aider ${REQ_VER} ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir "aider-chat==${REQ_VER}"
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
- Aider is installed in an isolated venv at /opt/aider.
- Configure API keys via environment variables:
    OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.
- See: https://aider.chat/
EON
