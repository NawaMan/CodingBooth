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
VERSION=$(curl -fsSL --connect-timeout 10 --max-time 60 \
    --retry 5 --retry-delay 3 --retry-all-errors "${GCS_BUCKET}/latest")
echo "Version: ${VERSION}"

# Download manifest and extract checksum
echo "Fetching manifest..."
MANIFEST=$(curl -fsSL --connect-timeout 10 --max-time 60 \
    --retry 5 --retry-delay 3 --retry-all-errors "${GCS_BUCKET}/${VERSION}/manifest.json")

CHECKSUM=""
SIZE=""
if command -v jq &>/dev/null; then
    # The platforms live under a "platforms" object, not at the top level. Reading
    # them from the root yields empty — and since jq is present in the base image,
    # the regex fallback never ran to cover for it, so every build installed an
    # unverified binary.
    CHECKSUM=$(echo "$MANIFEST" | jq -r ".platforms.\"${PLATFORM}\".checksum // empty")
    SIZE=$(echo "$MANIFEST" | jq -r ".platforms.\"${PLATFORM}\".size // empty")
else
    # Fallback: extract checksum using bash regex (from official script)
    MANIFEST_NORMALIZED=$(echo "$MANIFEST" | tr -d '\n\r\t' | sed 's/ \+/ /g')
    if [[ $MANIFEST_NORMALIZED =~ \"$PLATFORM\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
        CHECKSUM="${BASH_REMATCH[1]}"
    fi
    if [[ $MANIFEST_NORMALIZED =~ \"$PLATFORM\"[^}]*\"size\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        SIZE="${BASH_REMATCH[1]}"
    fi
fi

if [[ -z "$CHECKSUM" ]]; then
    echo "❌ No checksum for '${PLATFORM}' in the manifest; refusing to install unverified." >&2
    exit 1
fi

# Download binary
BINARY_URL="${GCS_BUCKET}/${VERSION}/${PLATFORM}/claude"
BINARY_FILE="claude-${VERSION}-${PLATFORM}"
# The binary is ~330MB. Say so: on a slow link this single step runs for the best
# part of an hour, and a quiet curl makes that indistinguishable from a hang.
if [[ -n "$SIZE" ]]; then
    echo "Downloading from ${BINARY_URL} ($((SIZE / 1024 / 1024)) MB)..."
else
    echo "Downloading from ${BINARY_URL}..."
fi
# Start clean so -C - is purely a resume-across-retries mechanism: against a
# stale complete file the range request would come back 416 and -f would fail.
# A run that dies between the download and the mv below leaves exactly that.
rm -f "$BINARY_FILE"
# --speed-limit/--speed-time abort a transfer that has genuinely died rather than
# hanging on it forever; a slow-but-moving link stays under the threshold and is
# left alone. -C - resumes across retries so a reset partway does not restart
# 330MB from zero. The checksum below is what makes resuming safe.
curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 60 \
    --retry 5 --retry-delay 3 --retry-all-errors -C - \
    -o "$BINARY_FILE" "$BINARY_URL"

# Verify checksum
echo "Verifying checksum..."
echo "$CHECKSUM  $BINARY_FILE" | sha256sum -c - || {
    echo "Checksum verification failed!"
    rm -f "$BINARY_FILE"
    exit 1
}

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
# Credential and config seeding is handled by booth-entry's smart_copy.
# This script only ensures the ~/.claude directory and symlink exist.

CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

mkdir -p "/home/coder/.local/bin"
if [[ ! -e "/home/coder/.local/bin/claude" ]]; then
    ln -s /usr/local/bin/claude "/home/coder/.local/bin/claude"
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
echo '      # Claude Code config (home-seeding: onboarding state, theme, etc.)'
echo '      "-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro",'
echo '      # Claude Code credentials (home-override: always use fresh host credentials)'
echo '      "-v", "~/.claude/.credentials.json:/etc/cb-home/.claude/.credentials.json:ro"'
echo '  ]'
echo ""
echo "Seed the single credential file, not the whole ~/.claude: that directory also"
echo "holds session history and project state, which do not belong in a booth. And"
echo "seed it through /etc/cb-home (override), not /etc/cb-home-seed (no-clobber),"
echo "so a refreshed host token reaches the booth instead of losing to a stale copy."
echo ""
