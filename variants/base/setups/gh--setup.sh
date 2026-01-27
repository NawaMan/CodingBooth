#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs GitHub CLI (gh) at BUILD time
# https://cli.github.com/
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

SCRIPT_NAME="$(basename "$0")"

# --- Defaults ---
GH_VERSION="${1:-latest}"

STARTUP_FILE="/usr/share/startup.d/60-cb-gh--startup.sh"
PROFILE_FILE="/etc/profile.d/60-cb-gh--profile.sh"

# ==== Install GitHub CLI ====

echo "Installing GitHub CLI..."

# Add GitHub CLI repository
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

# Install gh
apt-get update
apt-get install -y gh
rm -rf /var/lib/apt/lists/*

# Get installed version
INSTALLED_VERSION=$(gh --version | head -1 | awk '{print $3}')

# ---- Create startup file: runs once per container start as normal user ----
export GH_INSTALLED_VERSION="$INSTALLED_VERSION"
envsubst '$GH_INSTALLED_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# GitHub CLI startup script
# Copies credentials from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.config/gh"
GH_CONFIG_DIR="$HOME/.config/gh"

if [[ -d "$CB_SEED_DIR" && ! -d "$GH_CONFIG_DIR" ]]; then
    mkdir -p "$GH_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$GH_CONFIG_DIR/"
    chmod 600 "$GH_CONFIG_DIR/hosts.yml" 2>/dev/null || true
fi
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: sourced at beginning of user shell session ----
envsubst '$GH_INSTALLED_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: GitHub CLI: $GH_INSTALLED_VERSION
# gh is installed system-wide - no PATH modification needed

# Enable gh completion if available
if command -v gh &>/dev/null; then
    eval "$(gh completion -s bash 2>/dev/null)" || true
fi
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "GitHub CLI installed successfully!"
echo "  Version: ${INSTALLED_VERSION}"
echo "  Binary:  $(which gh)"
echo "  Startup: ${STARTUP_FILE}"
echo "  Profile: ${PROFILE_FILE}"
echo ""
echo "To authenticate: gh auth login"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # GitHub CLI credentials (home-seeding: gh may refresh tokens)'
echo '      "-v", "~/.config/gh:/etc/cb-home-seed/.config/gh:ro"'
echo '  ]'
echo ""
