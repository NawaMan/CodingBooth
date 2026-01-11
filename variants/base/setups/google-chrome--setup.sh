#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# chrome--setup.sh — Install Google Chrome (DEB, no snap) with no-sandbox wrapper
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

arch="$(dpkg --print-architecture)"   # arm64
if [[ "$arch" == "arm64" ]]; then
  echo "Chrom installation is not supported."
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

echo "🔧 Installing Google Chrome (DEB repo, no snap)…"

# add Google’s key + repo (idempotent)
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /etc/apt/keyrings/google-linux-signing-keyring.gpg
chmod 0644 /etc/apt/keyrings/google-linux-signing-keyring.gpg

arch="$(dpkg --print-architecture)"   # amd64 or arm64
cat > /etc/apt/sources.list.d/google-chrome.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/google-linux-signing-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main
EOF
chmod 0644 /etc/apt/sources.list.d/google-chrome.list

# install Chrome stable
apt-get update
apt-get install -y google-chrome-stable
echo "✅ Google Chrome installed"

# wrapper (always no-sandbox in container)
cat >/usr/local/bin/google-chrome <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/google-chrome-stable \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --no-first-run \
  --no-default-browser-check \
  --password-store=basic \
  --user-data-dir="${HOME}/.chrome-data" \
  "$@"
EOF
chmod 755 /usr/local/bin/google-chrome

# point desktop launcher (if present) to wrapper
if [[ -f /usr/share/applications/google-chrome.desktop ]]; then
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/google-chrome %U#' /usr/share/applications/google-chrome.desktop || true
fi

# --- make Chrome the default x-www-browser (preferred) ---
# Register Chrome with higher priority and set it as the default alternative.
update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/google-chrome 300
update-alternatives --set                            x-www-browser /usr/local/bin/google-chrome || true

echo "✅ Google Chrome set as the default Web Browser (x-www-browser)"
