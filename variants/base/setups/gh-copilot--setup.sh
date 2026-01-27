#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup - installs GitHub Copilot CLI extension at BUILD time
# Requires: gh (GitHub CLI) - run gh--setup.sh first
# https://docs.github.com/en/copilot/github-copilot-in-the-cli
# --------------------------
[ "$EUID" -eq 0 ] || { echo "Run as root (use sudo)"; exit 1; }

SCRIPT_NAME="$(basename "$0")"

# Check if gh is installed
if ! command -v gh &>/dev/null; then
    echo "ERROR: $SCRIPT_NAME requires GitHub CLI (gh)."
    echo "       Run gh--setup.sh first."
    exit 1
fi

STARTUP_FILE="/usr/share/startup.d/71-cb-gh-copilot--startup.sh"
PROFILE_FILE="/etc/profile.d/71-cb-gh-copilot--profile.sh"

# ==== Install GitHub Copilot CLI Extension ====

echo "Installing GitHub Copilot CLI extension..."

# Install the extension system-wide
# Extensions are installed per-user, so we install to a shared location
# and symlink in startup

GH_EXTENSIONS_DIR="/opt/gh-extensions"
mkdir -p "$GH_EXTENSIONS_DIR"

# Set GH_CONFIG_DIR temporarily to install extension to shared location
export GH_CONFIG_DIR="$GH_EXTENSIONS_DIR"
gh extension install github/gh-copilot || {
    echo "Note: Extension install may require authentication at runtime"
}

# ---- Create startup file: runs once per container start as normal user ----
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# GitHub Copilot CLI startup script
# Links system-wide extension to user's gh config

SYSTEM_EXT_DIR="/opt/gh-extensions/extensions/gh-copilot"
USER_EXT_DIR="$HOME/.local/share/gh/extensions/gh-copilot"

# If system extension exists and user doesn't have it, link it
if [[ -d "$SYSTEM_EXT_DIR" && ! -e "$USER_EXT_DIR" ]]; then
    mkdir -p "$(dirname "$USER_EXT_DIR")"
    ln -sf "$SYSTEM_EXT_DIR" "$USER_EXT_DIR"
fi

# If system install failed, try installing for user (requires auth)
if ! gh extension list 2>/dev/null | grep -q copilot; then
    if gh auth status &>/dev/null; then
        gh extension install github/gh-copilot 2>/dev/null || true
    fi
fi
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: sourced at beginning of user shell session ----
cat > "${PROFILE_FILE}" <<'EOF'
# Profile: GitHub Copilot CLI
# Usage: gh copilot suggest "how do I list files"
#        gh copilot explain "git rebase -i HEAD~3"

# Aliases for convenience
alias copilot='gh copilot'
alias '??'='gh copilot suggest'
alias 'explain'='gh copilot explain'
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "GitHub Copilot CLI extension installed!"
echo "  Startup: ${STARTUP_FILE}"
echo "  Profile: ${PROFILE_FILE}"
echo ""
echo "Usage:"
echo "  gh copilot suggest \"how do I find large files\""
echo "  gh copilot explain \"tar -xzf archive.tar.gz\""
echo ""
echo "Shortcuts (after shell restart):"
echo "  ?? \"your question\"     - suggest a command"
echo "  explain \"command\"      - explain a command"
echo ""
echo "Note: Requires 'gh auth login' and Copilot subscription"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse GitHub Copilot credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # GitHub Copilot credentials (home-seeding: may update tokens)'
echo '      "-v", "~/.config/github-copilot:/etc/cb-home-seed/.config/github-copilot:ro",'
echo '      # Also need GitHub CLI credentials'
echo '      "-v", "~/.config/gh:/etc/cb-home-seed/.config/gh:ro"'
echo '  ]'
echo ""
