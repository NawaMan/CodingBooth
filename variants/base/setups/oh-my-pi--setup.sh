#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest oh-my-pi (omp)
  $0 --version 17.0.7        # pin a specific version

Notes:
- Installs Oh My Pi (omp), a terminal AI coding agent with LSP, subagents,
  hashline edits, browser tools, and multi-provider model routing.
- Binary name: omp
- Config/auth live under ~/.omp (agent.db holds OAuth/API credentials).
- See: https://omp.sh  and  https://github.com/can1357/oh-my-pi
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) OMP_ARCH="x64" ;;
  arm64) OMP_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

REPO="can1357/oh-my-pi"
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

if [[ -z "$VERSION" ]]; then
  echo "❌ Failed to resolve oh-my-pi version" >&2
  exit 1
fi

BINARY="omp-linux-${OMP_ARCH}"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${BINARY}"
echo "⬇️  Installing Oh My Pi (omp) v${VERSION} (${BINARY}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 30 \
  -o "$TMP/omp" "$URL"
chmod +x "$TMP/omp"

if ! "$TMP/omp" --version </dev/null >/dev/null 2>&1; then
  echo "❌ Downloaded omp failed to run; aborting install." >&2
  exit 1
fi

install -m 755 "$TMP/omp" /usr/local/bin/omp

STARTUP_FILE="/usr/share/startup.d/70-cb-oh-my-pi--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-oh-my-pi--profile.sh"

# ---- Startup: ensure ~/.omp/agent exists (seed handled by booth-entry) ----
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Oh My Pi (omp) startup script
# Credential/config seeding is handled by booth-entry's smart_copy from
# /etc/cb-home-seed/.omp/ (see the credential extension). This only ensures
# the agent config directory exists so first-run works cleanly.

mkdir -p "$HOME/.omp/agent"
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Profile: short usage hint ----
cat > "${PROFILE_FILE}" <<EOF
# Profile: Oh My Pi (omp) v${VERSION}
#   omp                  # interactive coding agent TUI
#   omp -p "question"    # one-shot (print mode)
#   omp /login           # authenticate a provider (inside the TUI)
#
# Auth/settings live in ~/.omp/agent (agent.db + config.yml).
# API keys via env also work (ANTHROPIC_API_KEY, OPENAI_API_KEY, XAI_API_KEY, …).
# Docs: https://omp.sh
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "✅ Oh My Pi (omp) installed."
echo "   Version: ${VERSION}"
echo "   Binary:  /usr/local/bin/omp"
echo "   Startup: ${STARTUP_FILE}"
echo "   Profile: ${PROFILE_FILE}"
echo ""
echo "Usage:"
echo "  omp                     # interactive"
echo "  omp -p \"fix a bug\"    # one-shot"
echo ""
echo "=== Credential Seeding ==="
echo "To reuse credentials from the host, add to .booth/config.toml:"
echo ""
echo '  run-args = ['
echo '      # Oh My Pi auth store + settings (not sessions/logs/natives)'
echo '      "-v", "~/.omp/agent/agent.db:/etc/cb-home-seed/.omp/agent/agent.db:ro",'
echo '      "-v", "~/.omp/agent/config.yml:/etc/cb-home-seed/.omp/agent/config.yml:ro"'
echo '  ]'
echo ""
