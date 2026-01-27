#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs Claude Code at BUILD time
# Based on the official install script but for system-wide installation
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

# --- Defaults ---
CLAUDE_CODE_VERSION="${1:-latest}"

STARTUP_FILE="/usr/share/startup.d/70-cb-claude-code--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-claude-code--profile.sh"

# ==== Install Claude Code ====

GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Detect platform (same logic as official install script)
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH="x64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Check for musl libc
if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
    PLATFORM="linux-${ARCH}-musl"
else
    PLATFORM="linux-${ARCH}"
fi

echo "Installing Claude Code for ${PLATFORM}..."

cd /tmp

# Resolve version (same as official script - always use latest for most up-to-date installer)
echo "Fetching latest version..."
VERSION=$(curl -fsSL "${GCS_BUCKET}/latest")
echo "Version: ${VERSION}"

# Download manifest and extract checksum
echo "Fetching manifest..."
MANIFEST=$(curl -fsSL "${GCS_BUCKET}/${VERSION}/manifest.json")

CHECKSUM=""
if command -v jq &>/dev/null; then
    CHECKSUM=$(echo "$MANIFEST" | jq -r ".\"${PLATFORM}\".checksum // empty")
else
    # Fallback: extract checksum using bash regex (from official script)
    MANIFEST_NORMALIZED=$(echo "$MANIFEST" | tr -d '\n\r\t' | sed 's/ \+/ /g')
    if [[ $MANIFEST_NORMALIZED =~ \"$PLATFORM\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
        CHECKSUM="${BASH_REMATCH[1]}"
    fi
fi

# Download binary
BINARY_URL="${GCS_BUCKET}/${VERSION}/${PLATFORM}/claude"
BINARY_FILE="claude-${VERSION}-${PLATFORM}"
echo "Downloading from ${BINARY_URL}..."
curl -fsSL -o "$BINARY_FILE" "$BINARY_URL"

# Verify checksum
if [[ -n "$CHECKSUM" ]]; then
    echo "Verifying checksum..."
    echo "$CHECKSUM  $BINARY_FILE" | sha256sum -c - || {
        echo "Checksum verification failed!"
        rm -f "$BINARY_FILE"
        exit 1
    }
fi

chmod +x "$BINARY_FILE"

# Install system-wide (instead of user's ~/.local/bin)
echo "Installing to /usr/local/bin/claude..."
mv "$BINARY_FILE" /usr/local/bin/claude

# Verify
echo "Verifying installation..."
/usr/local/bin/claude --version || echo "(Version check may require user context)"

# ---- Create startup file: runs once per container start as normal user ----
export CLAUDE_CODE_VERSION="$VERSION"
envsubst '$CLAUDE_CODE_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Claude Code startup script
# Ensures config and credentials from cb-home-seed are properly copied

CB_SEED_DIR="/etc/cb-home-seed/.claude"
CB_SEED_JSON="/etc/cb-home-seed/.claude.json"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_JSON="$HOME/.claude.json"

mkdir -p "$CLAUDE_DIR"

# Copy .claude.json config file (contains hasCompletedOnboarding, theme, etc.)
# This must happen BEFORE claude runs to skip onboarding wizard
if [[ -f "$CB_SEED_JSON" && ! -f "$CLAUDE_JSON" ]]; then
    cp "$CB_SEED_JSON" "$CLAUDE_JSON"
fi

# Copy .claude/ directory contents (credentials, plugins, etc.)
if [[ -d "$CB_SEED_DIR" ]]; then
    # Use rsync if available (better merge), otherwise cp
    if command -v rsync &>/dev/null; then
        rsync -a --ignore-existing "$CB_SEED_DIR/" "$CLAUDE_DIR/"
    else
        # Copy files that don't exist in destination
        find "$CB_SEED_DIR" -type f | while read -r src; do
            rel="${src#$CB_SEED_DIR/}"
            dst="$CLAUDE_DIR/$rel"
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
envsubst '$CLAUDE_CODE_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: Claude Code: $CLAUDE_CODE_VERSION
# Installed system-wide in /usr/local/bin - no PATH modification needed
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "Claude Code installed successfully!"
echo "  Version: ${VERSION}"
echo "  Binary:  /usr/local/bin/claude"
echo "  Startup: ${STARTUP_FILE}"
echo "  Profile: ${PROFILE_FILE}"
echo ""
echo "Users can run 'claude' directly. Config will be set up on first run."
echo ""
echo "=== Credential Seeding ==="
echo "To reuse credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Claude Code config and credentials (home-seeding: may update tokens/session)'
echo '      "-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro",'
echo '      "-v", "~/.claude:/etc/cb-home-seed/.claude:ro"'
echo '  ]'
echo ""
