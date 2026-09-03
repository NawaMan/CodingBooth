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

usage() {
  cat <<USAGE
Usage:
  $0 [<version>|latest] [--version <version>|latest]

Examples:
  $0                  # track the cli.github.com apt repo (latest)
  $0 2.63.2           # pin the exact release
  $0 --version 2.63.2 # same, flag form
USAGE
}

# --- Defaults ---
GH_VERSION="${1:-latest}"
# A leading flag is not a positional version.
if [[ "${GH_VERSION}" =~ ^- ]]; then GH_VERSION="latest"; else shift || true; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; GH_VERSION="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

GH_VERSION="${GH_VERSION#v}"

STARTUP_FILE="/usr/share/startup.d/60-cb-gh--startup.sh"
PROFILE_FILE="/etc/profile.d/60-cb-gh--profile.sh"

# ==== Install GitHub CLI ====

if [[ "${GH_VERSION}" == "latest" ]]; then
  echo "Installing GitHub CLI (latest from cli.github.com)..."

  # Add GitHub CLI repository
  # `-o` rather than `| dd of=`: curl writes the file itself, so a retried
  # transfer overwrites cleanly instead of appending to a partial one.
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

  # Install gh
  apt-get update
  apt-get install -y gh
  rm -rf /var/lib/apt/lists/*
else
  # Pin an exact release: the apt repo only carries recent builds, so take the
  # .deb straight from the release that was asked for.
  dpkgArch="$(dpkg --print-architecture)"
  case "$dpkgArch" in
    amd64) GH_ARCH="amd64" ;;
    arm64) GH_ARCH="arm64" ;;
    *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
  esac

  DEB_FILE="/tmp/gh_${GH_VERSION}_${GH_ARCH}.deb"
  DEB_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.deb"

  echo "Installing GitHub CLI ${GH_VERSION}..."
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "$DEB_FILE" "$DEB_URL"

  apt-get update
  apt-get install -y --no-install-recommends "$DEB_FILE" || {
    # Fix broken dependencies if needed
    apt-get install -f -y --no-install-recommends
  }
  rm -f "$DEB_FILE"
  rm -rf /var/lib/apt/lists/*
fi

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
