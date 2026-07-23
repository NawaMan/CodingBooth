#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs Google Gemini CLI at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

HOME=/root

GEMINI_CLI_VERSION="${1:-latest}"
GEMINI_NPM_PKG="@google/gemini-cli"
STARTUP_FILE="/usr/share/startup.d/70-cb-gemini-cli--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-gemini-cli--profile.sh"

if ! command -v npm &>/dev/null; then
  echo "ERROR: gemini-cli--setup.sh requires npm."
  echo "Run nodejs--setup.sh first."
  exit 1
fi

echo "Installing Gemini CLI (${GEMINI_NPM_PKG}@${GEMINI_CLI_VERSION})..."
if [[ "$GEMINI_CLI_VERSION" == "latest" ]]; then
  npm install -g "${GEMINI_NPM_PKG}"
else
  npm install -g "${GEMINI_NPM_PKG}@${GEMINI_CLI_VERSION}"
fi

echo "Verifying installation..."
gemini --version || echo "(Version check may require user context)"

cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Gemini CLI startup — credential seed handled by booth-entry smart_copy.
mkdir -p "$HOME/.gemini"
EOF
chmod 755 "${STARTUP_FILE}"

cat > "${PROFILE_FILE}" <<EOF
# Profile: Gemini CLI (${GEMINI_NPM_PKG}@${GEMINI_CLI_VERSION})
#   gemini                   # interactive Gemini coding agent
#   gemini -p "prompt"       # one-shot (flags may vary by version)
#
# Auth: GEMINI_API_KEY / GOOGLE_API_KEY, or login in the TUI.
# Config: ~/.gemini/settings.json
# Docs: https://github.com/google-gemini/gemini-cli
#
# Note: Google access tiers change over time; API-key auth remains the
# most portable option inside a booth.
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "Gemini CLI installed successfully!"
echo "  Version: ${GEMINI_CLI_VERSION}"
echo "  Binary:  $(command -v gemini || echo '/usr/local/bin/gemini')"
echo "  Startup: ${STARTUP_FILE}"
echo ""
echo "=== Credential Seeding ==="
echo '  run-args = ['
echo '      "-v", "~/.gemini/settings.json:/etc/cb-home-seed/.gemini/settings.json:ro",'
echo '      "-v", "~/.gemini/oauth_creds.json:/etc/cb-home-seed/.gemini/oauth_creds.json:ro"'
echo '  ]'
echo ""
echo "Or pass a key at launch:"
echo "  GEMINI_API_KEY=... booth"
echo ""
