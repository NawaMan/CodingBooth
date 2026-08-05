#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# chromium-browser--setup.sh — Install Chromium (DEB, no snap) on Ubuntu via Debian Bookworm, then clean up
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root


export DEBIAN_FRONTEND=noninteractive

# Chromium comes from Debian Bookworm (Ubuntu's is a snap stub). The repo
# pinning and cleanup live in cb-install-chromium.sh so selenium and puppeteer
# can reuse the same install on arm64 without duplicating it.
cb-install-chromium.sh

# Discover chromium binary
CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
if [[ -z "$CHROMIUM_BIN" ]]; then
  echo "❌ Could not find chromium binary after installation" >&2
  exit 1
fi

# --- Chrome-compatible wrapper (no-sandbox for containers) ---
cat >/usr/local/bin/google-chrome <<EOF
#!/usr/bin/env bash
exec "$CHROMIUM_BIN" \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --no-first-run \
  --no-default-browser-check \
  --password-store=basic \
  --user-data-dir="\${HOME}/.chrome-data" \
  "\$@"
EOF
chmod 0755 /usr/local/bin/google-chrome
ln -sf "$CHROMIUM_BIN" /usr/local/bin/chromium-browser || true

# --- Optional: retarget .desktop to wrapper ---
if [[ -f /usr/share/applications/chromium.desktop ]]; then
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/google-chrome %U#' /usr/share/applications/chromium.desktop || true
fi

# --- Make default browser ---
update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/google-chrome 300
update-alternatives --set                            x-www-browser /usr/local/bin/google-chrome || true

echo "✅ Chromium set as the default Web Browser (x-www-browser)"

# Register a Chromium desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh chromium.desktop
