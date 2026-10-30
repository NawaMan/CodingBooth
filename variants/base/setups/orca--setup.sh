#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--port <PORT>]

Options:
  --version <ver>   Orca release to install (default: latest)
  --port <PORT>     Port 'orca-serve' listens on (default: 6768)

Examples:
  $0                          # latest release
  $0 --version 1.4.244        # pin a release
  $0 --port 6800              # headless server on another port

Notes:
- Installs Orca (https://www.onorca.dev/, https://github.com/stablyai/orca), an
  agent development environment, from its release .deb (sha256-checked).
- One install, two ways to use it:
    • desktop variants: the Orca app, on the desktop and in the menu
    • any variant:      'orca-serve', a headless Orca runtime with a web client;
                        open its pairing link in the host browser, or add it to
                        the host's Orca under Settings → Remote Orca Servers
- The CLI is 'orca-ide' (upstream's Linux name, clear of GNOME's Orca screen reader).
- Supports amd64 and arm64.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
ORCA_DEFAULT_VER="1.4.244"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
ORCA_PORT="6768"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --port)    shift; ORCA_PORT="${1:-6768}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

SERVE_FILE="/usr/local/bin/orca-serve"
PAIRING_FILE="/usr/local/bin/orca-pairing"
SERVE_LOG="/tmp/orca-serve.log"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) : ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive

# ---- resolve version + checksum ----
# The release API carries each asset's sha256 digest, so one call gives both.
API="https://api.github.com/repos/stablyai/orca/releases"
if [[ "$REQ_VER" == "latest" ]]; then API="${API}/latest"; else API="${API}/tags/v${REQ_VER}"; fi
RELEASE_JSON="$(curl --retry 3 --retry-delay 2 -fsSL "$API" || true)"

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION="$(printf '%s' "$RELEASE_JSON" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
             | sed -E 's/.*"v([^"]+)".*/\1/' || true)"
  if [[ -z "$VERSION" ]]; then
    # The GitHub API is rate-limited; degrade to the pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest Orca release; using ${ORCA_DEFAULT_VER}."
    VERSION="$ORCA_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

ASSET="orca-ide_${VERSION}_${dpkgArch}.deb"
EXPECTED=""
if command -v jq >/dev/null 2>&1 && [[ -n "$RELEASE_JSON" ]]; then
  EXPECTED="$(printf '%s' "$RELEASE_JSON" \
              | jq -r --arg a "$ASSET" '.assets[]? | select(.name == $a) | .digest // empty' 2>/dev/null \
              | sed -n 's/^sha256://p' | head -1 || true)"
fi

# ---- download + install the .deb ----
DEB_FILE="/tmp/${ASSET}"
echo "⬇️  Downloading Orca v${VERSION} (${dpkgArch}) ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/stablyai/orca/releases/download/v${VERSION}/${ASSET}" -o "$DEB_FILE"

ACTUAL="$(sha256sum "$DEB_FILE" | awk '{ print $1 }')"
if [[ -n "$EXPECTED" ]]; then
  [[ "$EXPECTED" == "$ACTUAL" ]] \
    || { echo "❌ Checksum mismatch for ${ASSET} (expected ${EXPECTED}, got ${ACTUAL})"; exit 1; }
  echo "🔒 sha256 verified: ${ACTUAL}"
else
  echo "⚠️  Could not read the release digest (GitHub API unreachable); sha256 of what was installed: ${ACTUAL}"
fi

echo "📦 Installing Orca ..."
apt-get update
# The .deb leaves out two libraries Electron links against on 26.04: without
# libasound2t64 even the CLI ('orca-ide serve') fails to load; libgbm1 is the GPU buffer API.
apt-get install -y --no-install-recommends "$DEB_FILE" libasound2t64 libgbm1
rm -f "$DEB_FILE"
rm -rf /var/lib/apt/lists/*

INSTALLED_VERSION="$(dpkg -s orca-ide 2>/dev/null | awk '/^Version:/ { print $2 }' || echo "unknown")"

# ---- headless server starter ----
# The pairing link is the credential and is printed only when the server starts,
# so the log is kept where orca-pairing can find it again.
# --pairing-address is the address the link tells clients to dial. Inside a booth
# that is the published host port on localhost, not the container's IP: the
# orca+expose extension passes that port in as ORCA_HOST_PORT.
cat > "${SERVE_FILE}" <<'SERVE'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-${ORCA_PORT:-__ORCA_PORT__}}
[[ $# -gt 0 ]] && shift
HOST_PORT="${ORCA_HOST_PORT:-$PORT}"
# A relative host port (+OFFSET) is resolved on the host only; it cannot be advertised.
if [[ "$HOST_PORT" == +* ]]; then
  echo "⚠️  Host port '$HOST_PORT' is relative; advertising $PORT. Set ORCA_PAIRING_ADDRESS to override." >&2
  HOST_PORT="$PORT"
fi
PAIRING_ADDRESS="${ORCA_PAIRING_ADDRESS:-localhost:${HOST_PORT}}"

echo "Starting Orca server on port $PORT (pairing address: $PAIRING_ADDRESS) ..."
exec orca-ide serve --port "$PORT" --pairing-address "$PAIRING_ADDRESS" "$@"
SERVE
sed -i "s/__ORCA_PORT__/${ORCA_PORT}/g" "${SERVE_FILE}"
chmod 755 "${SERVE_FILE}"

cat > "${PAIRING_FILE}" <<PAIRING
#!/usr/bin/env bash
# Print the pairing links of the auto-started Orca server.
LOG="${SERVE_LOG}"
has_link() { grep -qE '^(Web client URL|Pairing URL):' "\$LOG" 2>/dev/null; }
# The server takes ~20s to print its link; while one is running, wait for it
# (up to ORCA_PAIRING_WAIT seconds) instead of reporting that there is none.
WAIT="\${ORCA_PAIRING_WAIT:-90}"
if ! has_link && pgrep -f 'out/cli/index.js serve' >/dev/null; then
  echo "⏳ Orca server is starting; waiting for its pairing link ..." >&2
  for _ in \$(seq 1 "\$WAIT"); do
    has_link && break
    pgrep -f 'out/cli/index.js serve' >/dev/null || break
    sleep 1
  done
fi
if ! has_link; then
  echo "No pairing link yet — is the Orca server running? (log: \$LOG)" >&2
  echo "Start it with: orca-serve   (or select the orca+serve extension)" >&2
  exit 1
fi
grep -E '^(Web client URL|Pairing URL):' "\$LOG" | tail -2
PAIRING
chmod 755 "${PAIRING_FILE}"

# ---- desktop app: run without Chromium's sandbox ----
# A container cannot create the namespaces Chromium's sandbox needs, so the app
# aborts at its zygote ("Failed to move to new namespace"). Turn the sandbox off
# for Orca only, the way cursor--setup.sh does: in its launcher, and in a wrapper
# ahead of /usr/bin on PATH so 'orca-ide open' starts the app the same way. The
# CLI itself runs Electron as plain Node, which the variable does not touch.
DESKTOP_FILE=/usr/share/applications/orca-ide.desktop
if [[ -f "$DESKTOP_FILE" ]]; then
  sed -i -E 's|^Exec=(/opt/Orca/orca-ide)|Exec=env ELECTRON_DISABLE_SANDBOX=1 \1|' "$DESKTOP_FILE"
fi
cat > /usr/local/bin/orca-ide <<'WRAPPER'
#!/usr/bin/env bash
export ELECTRON_DISABLE_SANDBOX=1
exec /usr/bin/orca-ide "$@"
WRAPPER
chmod 755 /usr/local/bin/orca-ide

# Register the Orca app on the desktop (no-op on non-desktop variants).
cb-desktop-icon.sh orca-ide.desktop

# ---- friendly summary ----
echo ""
echo "✅ Orca installed."
echo "   Version: ${INSTALLED_VERSION}"
echo "   CLI:     $(command -v orca-ide || echo /usr/bin/orca-ide)"
echo "   Server:  ${SERVE_FILE} (port ${ORCA_PORT})"

cat <<EON
ℹ️ Ready to use:
- Desktop variants: launch Orca from the desktop or menu
- Any variant:      orca-serve      # headless Orca runtime on port ${ORCA_PORT}
                    orca-pairing    # print its web-client and pairing links
- Agent accounts on the server: orca-ide account add --agent claude

Notes:
- The pairing link grants access to this booth's Orca: treat it like a password.
- See: https://www.onorca.dev/docs
EON
