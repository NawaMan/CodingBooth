#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--no-completion]

Examples:
  $0                       # install latest Azure CLI
  $0 --version 2.67.0      # pin specific version
  $0 --no-completion       # skip bash completion

Notes:
- Installs official Azure CLI (az) via Microsoft apt repository.
- Uses standard ~/.azure for user config.
- Version format: X.Y.Z (e.g., 2.67.0)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VERSION="latest"
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VERSION="${1:-latest}"; shift ;;
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates apt-transport-https gnupg lsb-release

# ---- add Microsoft apt repo ----
install -d /usr/share/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg

DISTRO=$(lsb_release -cs 2>/dev/null || echo "jammy")
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $DISTRO main" \
  > /etc/apt/sources.list.d/azure-cli.list

apt-get update
if [[ "$REQ_VERSION" != "latest" ]]; then
  if [[ ! "$REQ_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like X.Y.Z (e.g., 2.67.0)"; exit 2
  fi
  echo "📌 Installing azure-cli version $REQ_VERSION ..."
  apt-get install -y --no-install-recommends "azure-cli=${REQ_VERSION}-1~${DISTRO}"
else
  echo "📦 Installing latest azure-cli ..."
  apt-get install -y --no-install-recommends azure-cli
fi
rm -rf /var/lib/apt/lists/*

# optional bash completion
if [[ $WITH_COMPLETION -eq 1 ]]; then
  install -d /etc/bash_completion.d
  if [[ -f /etc/bash_completion.d/azure-cli ]]; then
    echo "   Bash completion already installed."
  else
    cat > /etc/bash_completion.d/azure-cli <<'COMP'
_az_completer() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=( $(az completion bash 2>/dev/null) )
}
complete -F _az_completer az
COMP
  fi
fi

# ---- startup script for credential seeding ----
STARTUP_FILE="/usr/share/startup.d/60-cb-azure-cli--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Azure CLI startup script
# Copies credentials from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.azure"
AZURE_CONFIG_DIR="$HOME/.azure"

if [[ -d "$CB_SEED_DIR" && ! -d "$AZURE_CONFIG_DIR" ]]; then
    mkdir -p "$AZURE_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$AZURE_CONFIG_DIR/"
    chmod 600 "$AZURE_CONFIG_DIR/accessTokens.json" 2>/dev/null || true
    chmod 600 "$AZURE_CONFIG_DIR/msal_token_cache.json" 2>/dev/null || true
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- summary ----
echo "✅ Azure CLI installed."
echo -n "   az → "; az version 2>/dev/null | head -n 1 || true
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: az version
- Authenticate with:
    az login
    az account set --subscription <SUBSCRIPTION_ID>

Version pinning:
- List available versions: apt-cache madison azure-cli
- Install specific version: azure-cli--setup.sh --version 2.67.0
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse Azure credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Azure CLI credentials (home-seeding)'
echo '      "-v", "~/.azure:/etc/cb-home-seed/.azure:ro"'
echo '  ]'
echo ""
