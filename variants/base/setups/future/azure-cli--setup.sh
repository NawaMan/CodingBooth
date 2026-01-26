#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs Azure CLI at BUILD time
# https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

SCRIPT_NAME="$(basename "$0")"

STARTUP_FILE="/usr/share/startup.d/60-cb-azure-cli--startup.sh"
PROFILE_FILE="/etc/profile.d/60-cb-azure-cli--profile.sh"

# ==== Install Azure CLI ====

echo "Installing Azure CLI..."

export DEBIAN_FRONTEND=noninteractive

# Install dependencies
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    apt-transport-https \
    lsb-release \
    gnupg

# Add Microsoft signing key and repository
mkdir -p /etc/apt/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
chmod go+r /etc/apt/keyrings/microsoft.gpg

# Get Ubuntu codename
CODENAME=$(lsb_release -cs)

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${CODENAME} main" | \
    tee /etc/apt/sources.list.d/azure-cli.list

# Install Azure CLI
apt-get update
apt-get install -y azure-cli
rm -rf /var/lib/apt/lists/*

# Get installed version
INSTALLED_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")

# ---- Create startup file: runs once per container start as normal user ----
export AZ_VERSION="$INSTALLED_VERSION"
envsubst '$AZ_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Azure CLI startup script
# Copies credentials from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.azure"
AZURE_CONFIG_DIR="$HOME/.azure"

if [[ -d "$CB_SEED_DIR" && ! -d "$AZURE_CONFIG_DIR" ]]; then
    mkdir -p "$AZURE_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$AZURE_CONFIG_DIR/"
    chmod 600 "$AZURE_CONFIG_DIR"/*.json 2>/dev/null || true
fi
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: sourced at beginning of user shell session ----
envsubst '$AZ_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: Azure CLI: $AZ_VERSION
# az is installed system-wide - no PATH modification needed

# Enable az completion if available
if command -v az &>/dev/null; then
    eval "$(register-python-argcomplete az 2>/dev/null)" || true
fi
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "Azure CLI installed successfully!"
echo "  Version: ${INSTALLED_VERSION}"
echo "  Binary:  $(which az)"
echo "  Startup: ${STARTUP_FILE}"
echo "  Profile: ${PROFILE_FILE}"
echo ""
echo "To authenticate: az login"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse Azure credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Azure CLI credentials (home-seeding: az may refresh tokens)'
echo '      "-v", "~/.azure:/etc/cb-home-seed/.azure:ro"'
echo '  ]'
echo ""
