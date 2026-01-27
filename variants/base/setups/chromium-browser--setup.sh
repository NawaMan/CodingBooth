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

UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")"
ARCH="$(dpkg --print-architecture)"   # amd64 or arm64
echo "🔧 Installing Chromium (no Snap) on Ubuntu ${UBUNTU_CODENAME} for ${ARCH}…"

# --- Add Debian Bookworm repos (with signed-by) ---
install -d -m 0755 /etc/apt/sources.list.d
cat >/etc/apt/sources.list.d/debian-bookworm.list <<'EOF'
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm-updates main
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://security.debian.org/debian-security bookworm-security main
EOF
chmod 0644 /etc/apt/sources.list.d/debian-bookworm.list

# --- Prefer Ubuntu by default; only pull what we target from Bookworm ---
cat >/etc/apt/apt.conf.d/99default-release <<EOF
APT::Default-Release "${UBUNTU_CODENAME}";
EOF

apt-get update

# --- Install Chromium FROM Debian Bookworm (pulling its deps) ---
apt-get install -y --no-install-recommends -t bookworm chromium

# Discover chromium binary
CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
if [[ -z "$CHROMIUM_BIN" ]]; then
  echo "❌ Could not find chromium binary after installation" >&2
  exit 1
fi
echo "✅ Chromium installed at: $CHROMIUM_BIN"

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

# --- IMPORTANT: Remove Debian to avoid future conflicts ---
rm -f /etc/apt/sources.list.d/debian-bookworm.list
rm -f /etc/apt/apt.conf.d/99default-release
apt-get update
echo "🧹 Cleaned up Debian repos; system back to Ubuntu-only."
