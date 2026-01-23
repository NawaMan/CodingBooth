#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# antigravity--setup.sh — Install Antigravity from DEB repository, then set up wrapper for containers
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    echo "SKIP: $SCRIPT_NAME - desktop environment not available" >&2
    exit 42
fi

ANTIGRAVITY_NEW_BIN=/usr/bin/antigravity
ANTIGRAVITY_ORG_BIN=/usr/bin/antigravity-original

export DEBIAN_FRONTEND=noninteractive

# Install required dependencies
apt-get update
apt-get install -y curl gnupg apt-transport-https

# Add Antigravity GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
  gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg

# Add Antigravity APT repository
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
  tee /etc/apt/sources.list.d/antigravity.list > /dev/null

# Update and install
apt-get update
apt-get install -y antigravity

mv "${ANTIGRAVITY_NEW_BIN}" "$ANTIGRAVITY_ORG_BIN"

# --- AntiGravity-compatible wrapper (no-sandbox for containers) ---
cat >"${ANTIGRAVITY_NEW_BIN}" <<EOF
#!/usr/bin/env bash
exec "$ANTIGRAVITY_ORG_BIN" \
  --no-sandbox \
  "\${@:-/home/coder/code}"
EOF
chmod 0755 "${ANTIGRAVITY_NEW_BIN}"

# --- Update .desktop file to use our wrapper ---
DESKTOP_FILE="/usr/share/applications/antigravity.desktop"
if [[ -f "$DESKTOP_FILE" ]]; then
  # Replace /usr/share/antigravity/antigravity with our wrapper
  sed -i 's|Exec=/usr/share/antigravity/antigravity|Exec=/usr/bin/antigravity|g' "$DESKTOP_FILE"
fi
