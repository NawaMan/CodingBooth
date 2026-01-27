#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <2.X.Y>|latest] [--no-completion]

Examples:
  $0                         # install latest AWS CLI v2
  $0 --version 2.17.21       # pin specific version
  $0 --no-completion         # skip bash completion setup

Notes:
- Installs under /opt/aws-cli/aws-<version> and links /opt/aws-cli-stable
- Exposes 'aws' and 'aws_completer' via /usr/local/bin
- Supports amd64 and arm64
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
  amd64) AWS_ARCH="x86_64" ;;
  arm64) AWS_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip less groff
rm -rf /var/lib/apt/lists/*

# ---- dirs ----
INSTALL_PARENT=/opt/aws-cli
LINK_DIR=/opt/aws-cli-stable
BIN_DIR=/usr/local/bin
mkdir -p "$INSTALL_PARENT"

# ---- fetch installer zip ----
# URL patterns:
#  - latest:  https://awscli.amazonaws.com/awscli-exe-linux-<arch>.zip
#  - version: https://awscli.amazonaws.com/awscli-exe-linux-<arch>-<version>.zip
if [[ "$REQ_VER" == "latest" ]]; then
  ZIP_URL="https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip"
else
  if [[ ! "$REQ_VER" =~ ^2\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like 2.X.Y (e.g., 2.17.21)"; exit 2
  fi
  ZIP_URL="https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}-${REQ_VER}.zip"
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading AWS CLI v2 ($REQ_VER, ${AWS_ARCH}) ..."
curl -fsSL "$ZIP_URL" -o "$TMP/awscliv2.zip"

echo "📦 Extracting ..."
unzip -q "$TMP/awscliv2.zip" -d "$TMP"

# Determine exact version from the extracted payload (aws/dist/VERSION)
if [[ -f "$TMP/aws/VERSION" ]]; then
  REAL_VER="$(tr -d '\n' < "$TMP/aws/VERSION")"
else
  # Fallback: query after install (shouldn't happen normally)
  REAL_VER="$REQ_VER"
fi

if [[ -z "$REAL_VER" || "$REAL_VER" == "latest" ]]; then
  echo "❌ Could not determine AWS CLI version"; exit 1
fi

TARGET_DIR="${INSTALL_PARENT}/aws-${REAL_VER}"
echo "🛠  Installing to ${TARGET_DIR} ..."
rm -rf "$TARGET_DIR"

# The official installer supports custom install and bin dirs
"$TMP/aws/install" -i "$TARGET_DIR" -b "$BIN_DIR"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# (Optional) bash completion
if [[ $WITH_COMPLETION -eq 1 ]]; then
  if command -v aws_completer >/dev/null 2>&1; then
    install -d /etc/bash_completion.d
    echo 'complete -C aws_completer aws' > /etc/bash_completion.d/aws_completer
  fi
fi

# ---- startup script for credential seeding ----
STARTUP_FILE="/usr/share/startup.d/60-cb-aws-cli--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# AWS CLI startup script
# Copies credentials from cb-home-seed if available

CB_SEED_DIR="/etc/cb-home-seed/.aws"
AWS_CONFIG_DIR="$HOME/.aws"

if [[ -d "$CB_SEED_DIR" && ! -d "$AWS_CONFIG_DIR" ]]; then
    mkdir -p "$AWS_CONFIG_DIR"
    cp -r "$CB_SEED_DIR/." "$AWS_CONFIG_DIR/"
    chmod 600 "$AWS_CONFIG_DIR/credentials" 2>/dev/null || true
fi
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- friendly summary ----
echo "✅ AWS CLI installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   aws --version → "; aws --version 2>/dev/null || true
command -v aws_completer >/dev/null && echo "   aws_completer  → $(command -v aws_completer)" || true
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: aws --version
- Bash completion: open a new shell or `source /etc/bash_completion.d/aws_completer`

Notes:
- This script installs the official AWS CLI v2 from awscli.amazonaws.com.
- Credentials & config are user-specific:
    aws configure
  or set env vars (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, ...).
- To update: re-run with --version <new> (keeps prior versions in /opt/aws-cli).

Uninstall a specific version:
  rm -rf /opt/aws-cli/aws-<version>
  # (optionally) update /opt/aws-cli-stable to point to another installed version
EON

echo ""
echo "=== Credential Seeding ==="
echo "To reuse AWS credentials from host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # AWS CLI credentials (home-seeding: credentials and config)'
echo '      "-v", "~/.aws:/etc/cb-home-seed/.aws:ro"'
echo '  ]'
echo ""
