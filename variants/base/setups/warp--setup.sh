#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs Warp terminal at BUILD time
# Warp is a modern terminal with AI features
# https://www.warp.dev/
# Requires: Desktop environment (X11/Wayland)
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"

# Check for desktop environment
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

STARTUP_FILE="/usr/share/startup.d/70-cb-warp--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-warp--profile.sh"

# ==== Install Warp ====

echo "Installing Warp terminal..."

# Detect architecture
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) WARP_ARCH="x86_64" ;;
    arm64) WARP_ARCH="aarch64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

cd /tmp

# Download Warp
# Warp provides a stable download URL
WARP_DEB="warp-terminal_${WARP_ARCH}.deb"
WARP_URL="https://releases.warp.dev/stable/v0.2024.11.12.08.02.stable_02/${WARP_DEB}"

echo "Downloading Warp for ${WARP_ARCH}..."

# Try the releases URL, fall back to app.warp.dev
if ! curl -fsSL -o "$WARP_DEB" "$WARP_URL" 2>/dev/null; then
    echo "Trying alternative download..."
    # Warp also provides downloads via their website
    curl -fsSL -o "$WARP_DEB" "https://app.warp.dev/download?package=deb" || {
        echo "ERROR: Failed to download Warp"
        exit 1
    }
fi

# Install dependencies and Warp
apt-get update
apt-get install -y -f ./"$WARP_DEB"
rm -f "$WARP_DEB"
rm -rf /var/lib/apt/lists/*

# Get installed version
INSTALLED_VERSION=$(dpkg -s warp-terminal 2>/dev/null | grep '^Version:' | awk '{print $2}' || echo "unknown")

# ---- Create startup file: runs once per container start as normal user ----
export WARP_VERSION="$INSTALLED_VERSION"
envsubst '$WARP_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Warp terminal startup script
# Copies config from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.warp"
WARP_CONFIG_DIR="$HOME/.warp"

if [[ -d "$CB_SEED_DIR" && ! -d "$WARP_CONFIG_DIR" ]]; then
    mkdir -p "$WARP_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$WARP_CONFIG_DIR/"
fi

# Also check for .local/share/warp-terminal
CB_SEED_DATA="/etc/cb-home-seed/.local/share/warp-terminal"
WARP_DATA_DIR="$HOME/.local/share/warp-terminal"

if [[ -d "$CB_SEED_DATA" && ! -d "$WARP_DATA_DIR" ]]; then
    mkdir -p "$WARP_DATA_DIR"
    cp -r "$CB_SEED_DATA/." "$WARP_DATA_DIR/"
fi
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: sourced at beginning of user shell session ----
envsubst '$WARP_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: Warp Terminal: $WARP_VERSION
# Warp is installed system-wide

# Set WARP_ENABLE_WAYLAND if running under Wayland
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    export WARP_ENABLE_WAYLAND=1
fi
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "Warp terminal installed successfully!"
echo "  Version: ${INSTALLED_VERSION}"
echo "  Binary:  $(which warp-terminal 2>/dev/null || echo '/usr/bin/warp-terminal')"
echo "  Startup: ${STARTUP_FILE}"
echo "  Profile: ${PROFILE_FILE}"
echo ""
echo "Launch Warp from the desktop menu or run: warp-terminal"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse Warp settings from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Warp terminal config (home-seeding: may update preferences)'
echo '      "-v", "~/.warp:/etc/cb-home-seed/.warp:ro",'
echo '      "-v", "~/.local/share/warp-terminal:/etc/cb-home-seed/.local/share/warp-terminal:ro"'
echo '  ]'
echo ""
