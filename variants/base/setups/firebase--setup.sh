#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--node-version <MAJOR>]

Examples:
  $0                     # install with Node.js 20 (default)
  $0 --node-version 22   # use Node.js 22

Notes:
- Installs Node.js and Firebase CLI (firebase-tools)
- Firebase CLI is installed globally via npm
- Supports amd64 and arm64
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
NODE_MAJOR=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-version) shift; NODE_MAJOR="${1:-20}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- check if nodejs is already installed ----
if command -v node >/dev/null 2>&1; then
  echo "• Node.js already installed: $(node --version)"
else
  # Install Node.js using the existing setup script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$SCRIPT_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js v${NODE_MAJOR} ..."
    "$SCRIPT_DIR/nodejs--setup.sh" "$NODE_MAJOR"
  else
    echo "❌ nodejs--setup.sh not found at $SCRIPT_DIR"
    exit 1
  fi
fi

# ---- install firebase-tools ----
echo "• Installing Firebase CLI (firebase-tools) ..."
npm install -g firebase-tools

# ---- startup script for credential seeding ----
STARTUP_FILE="/usr/share/startup.d/60-cb-firebase--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Firebase CLI startup script
# Copies credentials from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.config/configstore"
FIREBASE_CONFIG_DIR="$HOME/.config/configstore"

if [[ -d "$CB_SEED_DIR" && ! -d "$FIREBASE_CONFIG_DIR" ]]; then
    mkdir -p "$FIREBASE_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$FIREBASE_CONFIG_DIR/"
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- summary ----
echo "✅ Firebase CLI installed."
echo -n "   node → "; node --version
echo -n "   firebase → "; firebase --version
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: firebase --version
- Login: firebase login
- Initialize project: firebase init

Notes:
- Firebase CLI requires authentication for most operations
- Use 'firebase login --no-localhost' for headless environments
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse Firebase credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Firebase CLI credentials'
echo '      "-v", "~/.config/configstore:/etc/cb-home-seed/.config/configstore:ro"'
echo '  ]'
echo ""
