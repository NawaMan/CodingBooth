#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs Neovim at BUILD time
# https://neovim.io/
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

SCRIPT_NAME="$(basename "$0")"

# --- Defaults ---
NVIM_VERSION="${1:-stable}"  # stable, nightly, or specific version like v0.10.0

STARTUP_FILE="/usr/share/startup.d/70-cb-neovim--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-neovim--profile.sh"

# ==== Install Neovim ====

echo "Installing Neovim (${NVIM_VERSION})..."

export DEBIAN_FRONTEND=noninteractive

# Detect architecture
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) NVIM_ARCH="linux64" ;;
    arm64) NVIM_ARCH="linux64" ;;  # Neovim uses linux64 for both
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

cd /tmp

# Download Neovim
if [[ "$NVIM_VERSION" == "stable" ]]; then
    NVIM_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-${NVIM_ARCH}.tar.gz"
elif [[ "$NVIM_VERSION" == "nightly" ]]; then
    NVIM_URL="https://github.com/neovim/neovim/releases/download/nightly/nvim-${NVIM_ARCH}.tar.gz"
else
    # Specific version like v0.10.0
    NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-${NVIM_ARCH}.tar.gz"
fi

echo "Downloading from ${NVIM_URL}..."
curl -fsSL -o nvim.tar.gz "$NVIM_URL"

# Extract to /opt/nvim
echo "Extracting to /opt/nvim..."
rm -rf /opt/nvim
mkdir -p /opt/nvim
tar -xzf nvim.tar.gz -C /opt/nvim --strip-components=1
rm -f nvim.tar.gz

# Create symlinks
ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
ln -sf /opt/nvim/bin/nvim /usr/local/bin/vim  # Optional: make nvim the default vim

# Get installed version
INSTALLED_VERSION=$(/opt/nvim/bin/nvim --version | head -1 | awk '{print $2}')

# ---- Create startup file: runs once per container start as normal user ----
export NVIM_INSTALLED_VERSION="$INSTALLED_VERSION"
envsubst '$NVIM_INSTALLED_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Neovim startup script
# Copies config from cb-home-seed if available

CB_SEED_CONFIG="/etc/cb-home-seed/.config/nvim"
CB_SEED_DATA="/etc/cb-home-seed/.local/share/nvim"
CB_SEED_STATE="/etc/cb-home-seed/.local/state/nvim"

NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DATA="$HOME/.local/share/nvim"
NVIM_STATE="$HOME/.local/state/nvim"

# Copy config if not exists
if [[ -d "$CB_SEED_CONFIG" && ! -d "$NVIM_CONFIG" ]]; then
    mkdir -p "$NVIM_CONFIG"
    cp -r "$CB_SEED_CONFIG/." "$NVIM_CONFIG/"
fi

# Copy data (plugins, etc.) if not exists
if [[ -d "$CB_SEED_DATA" && ! -d "$NVIM_DATA" ]]; then
    mkdir -p "$NVIM_DATA"
    cp -r "$CB_SEED_DATA/." "$NVIM_DATA/"
fi

# Copy state if not exists
if [[ -d "$CB_SEED_STATE" && ! -d "$NVIM_STATE" ]]; then
    mkdir -p "$NVIM_STATE"
    cp -r "$CB_SEED_STATE/." "$NVIM_STATE/"
fi
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: sourced at beginning of user shell session ----
envsubst '$NVIM_INSTALLED_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: Neovim: $NVIM_INSTALLED_VERSION

# Set nvim as default editor
export EDITOR=nvim
export VISUAL=nvim

# Aliases
alias vi='nvim'
alias vim='nvim'
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "Neovim installed successfully!"
echo "  Version: ${INSTALLED_VERSION}"
echo "  Binary:  /opt/nvim/bin/nvim"
echo "  Symlink: /usr/local/bin/nvim, /usr/local/bin/vim"
echo "  Startup: ${STARTUP_FILE}"
echo "  Profile: ${PROFILE_FILE}"
echo ""
echo "Run 'nvim' to start. Config goes in ~/.config/nvim/"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse Neovim config from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Neovim config and plugins (home-seeding)'
echo '      "-v", "~/.config/nvim:/etc/cb-home-seed/.config/nvim:ro",'
echo '      "-v", "~/.local/share/nvim:/etc/cb-home-seed/.local/share/nvim:ro",'
echo '      "-v", "~/.local/state/nvim:/etc/cb-home-seed/.local/state/nvim:ro"'
echo '  ]'
echo ""
echo "Note: For large plugin directories, consider mounting directly instead:"
echo '  "-v", "~/.local/share/nvim:/home/coder/.local/share/nvim"'
echo ""
