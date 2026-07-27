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
# booth-entry already smart_copy's /etc/cb-home-seed in seed (no-clobber) mode.
# Firebase CLI often creates ~/.config/configstore/firebase-tools.json as "{}"
# (or empty) before a real login — that placeholder blocks the seed copy.
# This startup re-applies the host credential file when the dest is missing,
# empty, or only "{}". A real login in the container is left alone.
STARTUP_FILE="/usr/share/startup.d/60-cb-firebase--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Firebase CLI credentials from host home-seed.
# Overwrite dest only when missing / empty / placeholder "{}" so a real
# in-container login is not clobbered, but host creds still win over stubs.

# CB_FIREBASE_SEED_FILE is for unit tests; production leaves the default.
SEED_FILE="${CB_FIREBASE_SEED_FILE:-/etc/cb-home-seed/.config/configstore/firebase-tools.json}"
DEST_DIR="${HOME}/.config/configstore"
DEST_FILE="${DEST_DIR}/firebase-tools.json"

if [[ ! -f "$SEED_FILE" ]]; then
  exit 0
fi

need_copy=false
if [[ ! -f "$DEST_FILE" ]]; then
  need_copy=true
elif [[ ! -s "$DEST_FILE" ]]; then
  need_copy=true
else
  # Whitespace-only "{}" is Firebase's unauthenticated placeholder.
  content="$(tr -d '[:space:]' <"$DEST_FILE" 2>/dev/null || true)"
  if [[ "$content" == "{}" ]]; then
    need_copy=true
  fi
fi

if [[ "$need_copy" == true ]]; then
  mkdir -p "$DEST_DIR"
  cp "$SEED_FILE" "$DEST_FILE"
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
echo "To reuse Firebase credentials from host, add to .booth/config.toml"
echo "(or select firebase+credential in booth config):"
echo ""
echo '  run-args = ['
echo '      # Firebase CLI credentials (file mount; matches firebase+credential)'
echo '      "-v", "~/.config/configstore/firebase-tools.json:/etc/cb-home-seed/.config/configstore/firebase-tools.json:ro"'
echo '  ]'
echo ""
echo "Startup overwrites an empty or \"{}\" placeholder in the container with"
echo "the host file; a real login already in the container is left alone."
echo ""
