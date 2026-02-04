#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs OpenAI Codex CLI at BUILD time
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# --- Defaults ---
CODEX_VERSION="${1:-latest}"
CODEX_NPM_PKG="@openai/codex"
STARTUP_FILE="/usr/share/startup.d/70-cb-codex--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-codex--profile.sh"

if ! command -v npm &>/dev/null; then
    echo "ERROR: codex--setup.sh requires npm."
    echo "Run nodejs--setup.sh first."
    exit 1
fi

echo "Installing OpenAI Codex CLI (${CODEX_NPM_PKG}@${CODEX_VERSION})..."
if [[ "$CODEX_VERSION" == "latest" ]]; then
    npm install -g "${CODEX_NPM_PKG}"
else
    npm install -g "${CODEX_NPM_PKG}@${CODEX_VERSION}"
fi

echo "Verifying installation..."
codex --version || echo "(Version check may require user context)"

# ---- Create startup file: runs once per container start as normal user ----
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# OpenAI Codex startup script
# Ensures config and credentials from cb-home-seed are properly copied

CB_SEED_DIR="/etc/cb-home-seed/.codex"
CODEX_DIR="$HOME/.codex"

mkdir -p "$CODEX_DIR"

# Copy .codex/ directory contents (auth, config, etc.)
if [[ -d "$CB_SEED_DIR" ]]; then
    # Use rsync if available (better merge), otherwise cp
    if command -v rsync &>/dev/null; then
        rsync -a --ignore-existing "$CB_SEED_DIR/" "$CODEX_DIR/"
    else
        # Copy files that don't exist in destination
        find "$CB_SEED_DIR" -type f | while read -r src; do
            rel="${src#$CB_SEED_DIR/}"
            dst="$CODEX_DIR/$rel"
            if [[ ! -f "$dst" ]]; then
                mkdir -p "$(dirname "$dst")"
                cp "$src" "$dst"
            fi
        done
    fi
fi
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: sourced at beginning of user shell session ----
cat > "${PROFILE_FILE}" <<'EOF'
# Profile: OpenAI Codex CLI
# Installed system-wide in /usr/local/bin - no PATH modification needed
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "OpenAI Codex CLI installed successfully!"
echo "  Version: ${CODEX_VERSION}"
echo "  Binary:  $(command -v codex || echo '/usr/local/bin/codex')"
echo "  Startup: ${STARTUP_FILE}"
echo "  Profile: ${PROFILE_FILE}"
echo ""
echo "Users can run 'codex' directly. Config will be set up on first run."
echo ""
echo "=== Credential Seeding ==="
echo "To reuse credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # OpenAI Codex config and credentials (home-seeding: may update tokens/session)'
echo '      "-v", "~/.codex:/etc/cb-home-seed/.codex:ro"'
echo '  ]'
echo ""
