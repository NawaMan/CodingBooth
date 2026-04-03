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
  $0                         # install latest Ansible
  $0 --version 10.7.0        # pin specific version

Notes:
- Installs Ansible into an isolated venv at /opt/ansible
- Symlinks ansible, ansible-playbook, ansible-galaxy, ansible-vault, etc. to /usr/local/bin
- Requires python3 (will install via apt if missing)
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
VENV_DIR="/opt/ansible"
echo "🛠  Creating venv at ${VENV_DIR} ..."
python3 -m venv "$VENV_DIR"

if [[ "$REQ_VER" == "latest" ]]; then
  echo "⬇️  Installing latest Ansible ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir ansible
else
  echo "⬇️  Installing Ansible ${REQ_VER} ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir "ansible==${REQ_VER}"
fi

# ---- symlink binaries ----
echo "🔗 Creating symlinks in /usr/local/bin ..."
for bin in "$VENV_DIR"/bin/ansible*; do
  name="$(basename "$bin")"
  ln -sf "$bin" "/usr/local/bin/${name}"
done

# ---- friendly summary ----
INSTALLED_VER="$(/usr/local/bin/ansible --version 2>/dev/null | head -1 || echo "unknown")"
echo "✅ Ansible installed: ${INSTALLED_VER}"
echo -n "   ansible → "; command -v ansible

cat <<'EON'
ℹ️ Ready to use:
- Try: ansible --version
- Run a playbook: ansible-playbook playbook.yml

Notes:
- Ansible is installed in an isolated venv at /opt/ansible.
- All ansible-* binaries are symlinked to /usr/local/bin.
- See: https://docs.ansible.com/
EON
