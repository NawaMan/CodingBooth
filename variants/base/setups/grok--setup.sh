#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--channel <stable|alpha|enterprise>]

Examples:
  $0                              # install latest stable Grok Build
  $0 --version 0.2.111            # pin a specific version
  $0 --channel alpha              # install latest from the alpha channel

Notes:
- Installs the official xAI Grok Build coding agent CLI (binary: grok).
- Also installs the 'agent' alias (same binary), matching the upstream installer.
- Auth: run 'grok login' once, or seed ~/.grok/auth.json from the host.
- Env: GROK_DEPLOYMENT_KEY or tokens in ~/.grok/auth.json.
- See: https://x.ai/cli  and  https://x.ai/news/grok-build-cli
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
CHANNEL="stable"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --channel) shift; CHANNEL="${1:-stable}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$CHANNEL" in
  stable|alpha|enterprise) ;;
  *) echo "❌ Unknown channel: $CHANNEL (want stable|alpha|enterprise)" >&2; exit 2 ;;
esac

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) GROK_ARCH="x86_64" ;;
  arm64) GROK_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

BASE_URL_PRIMARY="https://x.ai/cli"
BASE_URL_FALLBACK="https://storage.googleapis.com/grok-build-public-artifacts/cli"

# Prefer Cloudflare-fronted x.ai; fall back to direct GCS if unreachable.
if curl -fsSL --connect-timeout 10 --max-time 30 "${BASE_URL_PRIMARY}/${CHANNEL}" >/tmp/cb-grok-channel.txt 2>/dev/null; then
  BASE_URL="$BASE_URL_PRIMARY"
else
  echo "Note: ${BASE_URL_PRIMARY} unreachable, falling back to GCS."
  BASE_URL="$BASE_URL_FALLBACK"
  curl -fsSL --connect-timeout 10 --max-time 30 "${BASE_URL}/${CHANNEL}" >/tmp/cb-grok-channel.txt
fi

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION="$(tr -d '[:space:]\r' </tmp/cb-grok-channel.txt)"
else
  VERSION="${REQ_VER#v}"
fi
rm -f /tmp/cb-grok-channel.txt

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._]+)?$ ]]; then
  echo "❌ Invalid Grok version: $VERSION" >&2
  exit 1
fi

ARTIFACT_URL="${BASE_URL}/grok-${VERSION}-linux-${GROK_ARCH}"
echo "⬇️  Installing Grok Build v${VERSION} (linux-${GROK_ARCH}, channel=${CHANNEL}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 30 \
  -o "$TMP/grok" "$ARTIFACT_URL"
chmod +x "$TMP/grok"

# Sanity-check the binary before replacing anything.
if ! "$TMP/grok" --version </dev/null >/dev/null 2>&1; then
  echo "❌ Downloaded grok failed to run; aborting install." >&2
  exit 1
fi

install -m 755 "$TMP/grok" /usr/local/bin/grok
# Upstream installer also exposes 'agent' as an alias of the same binary.
ln -sfn /usr/local/bin/grok /usr/local/bin/agent

STARTUP_FILE="/usr/share/startup.d/70-cb-grok--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-grok--profile.sh"

# ---- Startup: ensure ~/.grok exists (credential seed is handled by booth-entry) ----
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Grok Build startup script
# Credential/config seeding is handled by booth-entry's smart_copy from
# /etc/cb-home-seed/.grok/ (see the credential extension). This only ensures
# the config directory exists so first-run login works cleanly.

mkdir -p "$HOME/.grok"
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Profile: short usage hint ----
cat > "${PROFILE_FILE}" <<EOF
# Profile: Grok Build (xAI) v${VERSION}
#   grok                 # interactive coding agent TUI
#   grok "fix a bug"  # one-shot prompt
#   grok login           # authenticate (or seed ~/.grok/auth.json)
#   agent                # alias for grok
#
# Auth via ~/.grok/auth.json (from 'grok login') or GROK_DEPLOYMENT_KEY.
# Docs: https://x.ai/cli
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "✅ Grok Build installed."
echo "   Version: ${VERSION}"
echo "   Binary:  /usr/local/bin/grok  (alias: /usr/local/bin/agent)"
echo "   Startup: ${STARTUP_FILE}"
echo "   Profile: ${PROFILE_FILE}"
echo ""
echo "Usage:"
echo "  grok                  # interactive"
echo "  grok \"explain this\"   # one-shot"
echo "  grok login            # authenticate"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse credentials from the host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Grok Build auth + settings (not sessions/downloads/worktrees)'
echo '      "-v", "~/.grok/auth.json:/etc/cb-home-seed/.grok/auth.json:ro",'
echo '      "-v", "~/.grok/config.toml:/etc/cb-home-seed/.grok/config.toml:ro"'
echo '  ]'
echo ""
echo "Or pass a deployment key at launch:"
echo "  GROK_DEPLOYMENT_KEY=... booth"
echo ""
