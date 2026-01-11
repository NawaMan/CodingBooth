#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# firefox--setup.sh — Install Firefox via Mozillateam PPA (avoids snap)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "🔧 Installing Firefox (Mozillateam PPA, no snap)…"

# Remove any snap-stubbed Firefox
apt-get remove -y firefox || true

# Add Mozillateam PPA and pin it
apt-get update
add-apt-repository -y ppa:mozillateam/ppa
tee /etc/apt/preferences.d/mozillateam-firefox >/dev/null <<'EOF'
Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

# Install Firefox (DEB)
apt-get update
apt-get install -y firefox
echo "✅ Firefox installed (DEB, no snap)"

# --- register Firefox as an alternative, lower priority than Chrome ---
# We install the alternative, but only set it as default if Chrome isn't already the default.
update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/firefox 100

# If Chrome isn't present as the current choice, make Firefox the default.
current="$(readlink -f "$(command -v x-www-browser)" 2>/dev/null || true)"
if [[ "$current" != "/usr/local/bin/google-chrome" ]]; then
  update-alternatives --set x-www-browser /usr/bin/firefox || true
  echo "ℹ️ Firefox set as the default Web Browser (x-www-browser) (Chrome not found)."
else
  echo "ℹ️ Chrome already the default; Firefox registered with lower priority."
fi
