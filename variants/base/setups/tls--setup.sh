#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root


# --- Defaults ---
LEVEL=50                          # Early infrastructure, before variant services

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-tls--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-tls--profile.sh"

TLS_PROXY_PORT=10443
TLS_BACKEND_PORT=10000


# ==== Install Caddy ====

echo "📦 Installing Caddy..."
CADDY_VERSION=2.11.2
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) CADDY_ARCH="amd64" ;;
  arm64) CADDY_ARCH="arm64" ;;
  *)     echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

curl -fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5 \
  "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${CADDY_ARCH}.tar.gz" \
  -o /tmp/caddy.tar.gz
tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy
rm /tmp/caddy.tar.gz
chmod +x /usr/local/bin/caddy


# ==== Create startup hook ====
# Runs once per container start as the coder user.
# Only activates when BOOTH_TLS=true is set by the CLI.

cat > "${STARTUP_FILE}" <<'STARTUP_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Only start Caddy TLS proxy when explicitly enabled
[[ "${BOOTH_TLS:-}" == "true" ]] || exit 0

TLS_PROXY_PORT="${BOOTH_TLS_PROXY_PORT:-10443}"
TLS_BACKEND_PORT="${BOOTH_TLS_BACKEND_PORT:-10000}"
CADDY_DATA_DIR="${HOME}/.local/share/caddy"
CADDYFILE="/tmp/Caddyfile"

mkdir -p "${CADDY_DATA_DIR}"

# Generate Caddyfile
if [[ -n "${BOOTH_TLS_CERT:-}" && -n "${BOOTH_TLS_KEY:-}" ]]; then
    # User-provided certificates
    cat > "${CADDYFILE}" <<CADDY_CONF
:${TLS_PROXY_PORT} {
    tls ${BOOTH_TLS_CERT} ${BOOTH_TLS_KEY}
    reverse_proxy localhost:${TLS_BACKEND_PORT}
}
CADDY_CONF
    echo "🔒 TLS proxy starting with user-provided certificates"
else
    # Self-signed certificate (Caddy's internal CA)
    cat > "${CADDYFILE}" <<CADDY_CONF
:${TLS_PROXY_PORT} {
    tls internal {
        on_demand
    }
    reverse_proxy localhost:${TLS_BACKEND_PORT}
}
CADDY_CONF
    echo "🔒 TLS proxy starting with self-signed certificate"
fi

# Start Caddy in background
XDG_DATA_HOME="${HOME}/.local/share" caddy run --config "${CADDYFILE}" &>/tmp/caddy.log &
CADDY_PID=$!

# Wait briefly to verify startup
sleep 1
if kill -0 "$CADDY_PID" 2>/dev/null; then
    echo "✅ TLS proxy running on port ${TLS_PROXY_PORT} -> localhost:${TLS_BACKEND_PORT}"
else
    echo "⚠️  Warning: Caddy TLS proxy may not have started correctly"
    echo "   Check /tmp/caddy.log for details"
fi
STARTUP_EOF
chmod 755 "${STARTUP_FILE}"


# ==== Create profile script ====
cat > "${PROFILE_FILE}" <<PROFILE_EOF
# Profile: TLS Reverse Proxy (Caddy)
# Exports convenience variables when TLS is enabled

if [[ "\${BOOTH_TLS:-}" == "true" ]]; then
    export BOOTH_TLS_PROXY_PORT="${TLS_PROXY_PORT}"
    export BOOTH_TLS_BACKEND_PORT="${TLS_BACKEND_PORT}"
fi
PROFILE_EOF
chmod 644 "${PROFILE_FILE}"


# ==== Summary ====
echo ""
echo "✅ .... TLS Reverse Proxy (Caddy) is installed ...."
echo "• Startup file : ${STARTUP_FILE}"
echo "• Profile file : ${PROFILE_FILE}"
echo "• Proxy port   : ${TLS_PROXY_PORT} (HTTPS) -> ${TLS_BACKEND_PORT} (HTTP)"
echo ""
echo "NOTE: TLS proxy is only activated when BOOTH_TLS=true is set."
echo "      This is done automatically by the CLI when --public is used."
echo ""
