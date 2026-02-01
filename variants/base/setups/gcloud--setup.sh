#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <VERSION>] [--no-completion]

Examples:
  $0                       # install latest gcloud SDK
  $0 --version 504.0.1-0   # pin specific version
  $0 --no-completion       # skip bash completion

Notes:
- Installs official Google Cloud SDK (gcloud, gsutil, bq) via apt.
- Uses standard ~/.config/gcloud for user config.
- Version format: X.Y.Z-0 (e.g., 504.0.1-0)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VERSION=""
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VERSION="${1:-}"; shift ;;
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates apt-transport-https gnupg

# ---- add Google apt repo ----
install -d /usr/share/keyrings
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  > /etc/apt/sources.list.d/google-cloud-sdk.list

apt-get update
if [[ -n "$REQ_VERSION" ]]; then
  echo "📌 Installing google-cloud-cli version $REQ_VERSION ..."
  apt-get install -y --no-install-recommends "google-cloud-cli=$REQ_VERSION"
else
  echo "📦 Installing latest google-cloud-cli ..."
  apt-get install -y --no-install-recommends google-cloud-cli
fi
rm -rf /var/lib/apt/lists/*

# optional bash completion
if [[ $WITH_COMPLETION -eq 1 ]]; then
  install -d /etc/bash_completion.d
  gcloud completion bash > /etc/bash_completion.d/gcloud 2>/dev/null || true
fi

# ---- startup script for credential seeding ----
STARTUP_FILE="/usr/share/startup.d/60-cb-gcloud--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Google Cloud SDK startup script
# Copies credentials from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.config/gcloud"
GCLOUD_CONFIG_DIR="$HOME/.config/gcloud"

if [[ -d "$CB_SEED_DIR" && ! -d "$GCLOUD_CONFIG_DIR" ]]; then
    mkdir -p "$GCLOUD_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$GCLOUD_CONFIG_DIR/"
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- summary ----
echo "✅ Google Cloud SDK installed."
echo -n "   gcloud → "; gcloud version | head -n 1
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: gcloud version
- Authenticate with:
    gcloud auth login
    gcloud config set project <PROJECT_ID>

Version pinning:
- List available versions: apt-cache madison google-cloud-cli
- Install specific version: gcloud--setup.sh --version 504.0.1-0
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse gcloud credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      "-v", "~/.config/gcloud:/home/coder/.config/gcloud"'
echo '  ]'
echo ""
