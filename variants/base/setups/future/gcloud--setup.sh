#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--no-completion]

Examples:
  $0                  # install latest gcloud SDK
  $0 --no-completion  # skip bash completion

Notes:
- Installs official Google Cloud SDK (gcloud, gsutil, bq).
- Shared config at /opt/gcloud/config (CLOUDSDK_CONFIG).
- Exposes gcloud in PATH for all users.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
WITH_COMPLETION=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates apt-transport-https gnupg lsb-release bash-completion
rm -rf /var/lib/apt/lists/*

# ---- add Google apt repo ----
install -d /usr/share/keyrings
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
CODENAME="$(lsb_release -cs || echo noble)"
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  > /etc/apt/sources.list.d/google-cloud-sdk.list

apt-get update
apt-get install -y --no-install-recommends google-cloud-sdk
rm -rf /var/lib/apt/lists/*

# ---- shared config dir ----
install -d -m 0777 /opt/gcloud/config

# login-shell env
cat >/etc/profile.d/99-gcloud--profile.sh <<'EOF'
# Google Cloud SDK config location
export CLOUDSDK_CONFIG=/opt/gcloud/config
EOF
chmod 0644 /etc/profile.d/99-gcloud--profile.sh

# non-login wrapper (so CLOUDSDK_CONFIG is respected in Docker RUN)
install -d /usr/local/bin
cat >/usr/local/bin/gcloudwrap <<'EOF'
#!/bin/sh
: "${CLOUDSDK_CONFIG:=/opt/gcloud/config}"
export CLOUDSDK_CONFIG
exec /usr/bin/gcloud "$@"
EOF
chmod +x /usr/local/bin/gcloudwrap
ln -sfn /usr/local/bin/gcloudwrap /usr/local/bin/gcloud

# optional bash completion
if [[ $WITH_COMPLETION -eq 1 && -x /usr/bin/gcloud ]]; then
  install -d /etc/bash_completion.d
  /usr/bin/gcloud completion bash > /etc/bash_completion.d/gcloud || true
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
- Configs live in /opt/gcloud/config (shared by all users).
- Works in login & non-login shells (wrapper sets CLOUDSDK_CONFIG).
- Authenticate with:
    gcloud auth login
    gcloud config set project <PROJECT_ID>
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse gcloud credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Google Cloud credentials (home-seeding: gcloud may refresh tokens)'
echo '      "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro",'
echo '      "-e", "GOOGLE_APPLICATION_CREDENTIALS=/home/coder/.config/gcloud/application_default_credentials.json"'
echo '  ]'
echo ""




NOTE_ONLY=<<'NOTE'

To install the Google Cloud CLI (gcloud) on Ubuntu, follow these steps:

1. Update your package list and install the required packages:

  sudo apt-get update && sudo apt-get install -y curl apt-transport-https ca-certificates gnupg
     
2. Add the Google Cloud repository to your system. Use the signed-by option if your system supports it:

  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
 
3. Import the Google Cloud public key. If your system supports gpg --dearmor, use:

  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

If `gpg --dearmor` is not available, use `apt-key`:

  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
 
4. Update the package list and install the Google Cloud CLI:

  sudo apt-get update && sudo apt-get install google-cloud-cli
 
5. Initialize the gcloud CLI by running:

  gcloud init
 
This command will prompt you to log in to your Google Cloud account and select a project.

For installation within a Docker image, use a single RUN command to avoid issues with the apt-key command:

  RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && apt-get update -y && apt-get install google-cloud-cli -y
 
NOTE