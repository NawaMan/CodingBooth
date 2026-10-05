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
  $0                         # install latest Terraform
  $0 --version 1.9.5         # pin specific version
  $0 --no-completion         # skip bash completion setup

Notes:
- Installs Terraform binary to /usr/local/bin/terraform
- Supports amd64 and arm64
- Downloads from official HashiCorp releases
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip jq
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  echo "🔍 Resolving latest Terraform version ..."
  VERSION="$(curl --retry 3 --retry-delay 2 -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)"
  if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
    echo "❌ Failed to resolve latest Terraform version"; exit 1
  fi
  echo "   Latest version: ${VERSION}"
else
  if [[ ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like X.Y.Z (e.g., 1.9.5)"; exit 2
  fi
  VERSION="$REQ_VER"
fi

# ---- download and install ----
ZIP_URL="https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${ARCH}.zip"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading Terraform ${VERSION} (${ARCH}) ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$ZIP_URL" -o "$TMP/terraform.zip"

echo "📦 Extracting ..."
unzip -q "$TMP/terraform.zip" -d "$TMP"

echo "🛠  Installing to /usr/local/bin/terraform ..."
install -m 0755 "$TMP/terraform" /usr/local/bin/terraform

# ---- bash completion ----
if [[ $WITH_COMPLETION -eq 1 ]]; then
  install -d /etc/bash_completion.d
  # terraform -install-autocomplete modifies user shell rc files;
  # instead, generate a static completion script
  cat > /etc/bash_completion.d/terraform <<'COMP'
complete -C /usr/local/bin/terraform terraform
COMP
fi

# ---- startup script for credential seeding ----
STARTUP_FILE="/usr/share/startup.d/61-cb-terraform--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Terraform startup script
# Copies .terraformrc from cb-home-seed if available

CB_SEED_FILE="/etc/cb-home-seed/.terraformrc"
TF_RC="$HOME/.terraformrc"

if [[ -f "$CB_SEED_FILE" && ! -f "$TF_RC" ]]; then
    cp "$CB_SEED_FILE" "$TF_RC"
    chmod 600 "$TF_RC" 2>/dev/null || true
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- friendly summary ----
INSTALLED_VER="$(terraform --version | head -1)"
echo "✅ Terraform installed: ${INSTALLED_VER}"
echo "   Binary:  /usr/local/bin/terraform"
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: terraform --version
- Common commands:
    terraform init      # initialize a working directory
    terraform plan      # preview changes
    terraform apply     # apply changes
    terraform destroy   # tear down infrastructure
    terraform fmt       # format configuration files
    terraform validate  # validate configuration

Notes:
- This script installs the official Terraform binary from releases.hashicorp.com.
- Provider credentials are managed per provider (e.g., AWS, GCP, Azure).
- To update: re-run with --version <new>.
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse .terraformrc from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Terraform config (home-seeding: .terraformrc)'
echo '      "-v", "~/.terraformrc:/etc/cb-home-seed/.terraformrc:ro"'
echo '  ]'
echo ""
