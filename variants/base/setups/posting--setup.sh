#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install Posting ${POSTING_DEFAULT_VER}
  $0 --version latest        # install the latest release from PyPI
  $0 --version 2.11.0        # pin specific version

Notes:
- Installs Posting into an isolated venv at /opt/posting (what pipx/uv tool do)
- Symlinks posting to /usr/local/bin/posting
- Requires python3 >= 3.11 (installs python3 + venv via apt if missing)
- Ubuntu only packages posting from 26.04 on, so apt is not used for it
USAGE
}

# cb_retry retries the network-bound pip install past a transient registry
# error, and nothing else, so a bad version still fails on the first attempt.
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/retry-source.sh" ]; then
    SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/retry-source.sh"

# ---- defaults / args ----
POSTING_DEFAULT_VER="2.11.0"
REQ_VER="${POSTING_DEFAULT_VER}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-$POSTING_DEFAULT_VER}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- ensure python3 + venv ----
export DEBIAN_FRONTEND=noninteractive
if ! command -v python3 &>/dev/null || ! python3 -m venv --help &>/dev/null; then
  echo "📦 Installing python3 + venv ..."
  apt-get update
  apt-get install -y --no-install-recommends python3 python3-venv
  rm -rf /var/lib/apt/lists/*
fi

if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo "❌ Posting needs Python >= 3.11; found $(python3 --version 2>&1)" >&2
  exit 1
fi

# ---- create venv and install ----
VENV_DIR="/opt/posting"
echo "🛠  Creating venv at ${VENV_DIR} ..."
python3 -m venv "$VENV_DIR"

if [[ "$REQ_VER" == "latest" ]]; then
  echo "⬇️  Installing latest Posting ..."
  cb_retry "$VENV_DIR/bin/pip" install --no-cache-dir posting
else
  echo "⬇️  Installing Posting ${REQ_VER} ..."
  cb_retry "$VENV_DIR/bin/pip" install --no-cache-dir "posting==${REQ_VER}"
fi

# ---- symlink binary ----
echo "🔗 Creating symlink in /usr/local/bin ..."
ln -sf "$VENV_DIR/bin/posting" /usr/local/bin/posting

# ---- friendly summary ----
echo "✅ Posting installed."
# posting has no --version flag; ask the venv's pip instead.
echo -n "   posting → "; "$VENV_DIR/bin/pip" show posting 2>/dev/null | awk '/^Version:/ {print $2}' || true

cat <<'EON'
ℹ️ Ready to use:
- Open the TUI:           posting
- Use a collection dir:   posting --collection ./api-requests
- Import an OpenAPI spec: posting import openapi.yaml -o ./api-requests

Notes:
- Requests are saved as YAML files in the collection directory, so keep it
  inside the project to have them persist and go into version control.
- See: https://posting.sh/
EON
