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

# This script will always be installed by root.
HOME=/root


arch="$(dpkg --print-architecture)"   # amd64 or arm64
if [[ "$arch" == "arm64" ]]; then
  # Google ships no linux-arm64 build of Chrome — not in the DEB repo, and not
  # in Chrome for Testing. There is nothing to install and nothing we can do
  # about it here, so warn and carry on: a missing browser must not take the
  # whole build down when every other setup in the booth is fine.
  cat >&2 <<'WARN'

⚠️  Google Chrome is not available on arm64 — skipping.

    Google publishes no linux/arm64 build of Chrome (the DEB repo and Chrome
    for Testing are both x86-64 only), and this booth is being built for arm64
    — the default on Apple Silicon. The rest of the booth is unaffected.

    What to use instead:
      • setup chromium-browser  — Chromium, same engine, arm64 build available.
                                  Also provides a `google-chrome` command.
      • setup firefox           — Firefox, arm64 build available.
      • Google Chrome on your Mac — run it against the port your booth exposes
                                  and test the real thing in the real browser.

WARN

  # A runtime warning beats "command not found" for anyone who types
  # google-chrome or clicks a .desktop entry. Never clobber a real wrapper:
  # chromium-browser--setup.sh installs a working one at this same path.
  if [[ -e /usr/local/bin/google-chrome ]]; then
    echo "   (/usr/local/bin/google-chrome already provided by another setup — left as is.)" >&2
  else
    cat >/usr/local/bin/google-chrome <<'STUB'
#!/usr/bin/env bash
# Placeholder installed by google-chrome--setup.sh on arm64, where Google
# publishes no Linux build of Chrome. Explains itself instead of failing silently.
cat >&2 <<'MSG'
google-chrome is not installed: Google publishes no linux/arm64 build of Chrome,
and this booth runs on arm64 (the default on Apple Silicon).

Use instead:
  chromium        — same engine, arm64 build      (booth config: chromium)
  firefox         — arm64 build                   (booth config: firefox)
  Google Chrome on your host Mac, pointed at the port this booth exposes.
MSG
exit 127
STUB
    chmod 0755 /usr/local/bin/google-chrome
  fi
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

echo "🔧 Installing Google Chrome (DEB repo, no snap)…"

# add Google’s key + repo (idempotent)
# Desktop base images often already ship this keyring. Overwriting with
# `gpg --dearmor -o existing.gpg` (no --batch/--yes) prompts on /dev/tty, which
# does not exist in Docker builds → "cannot open '/dev/tty'" and curl (23).
# Fetch to a temp file and dearmor with --batch --yes (stdin/stdout).
install -d -m 0755 /etc/apt/keyrings
KEYRING=/etc/apt/keyrings/google-linux-signing-keyring.gpg
TMP_KEY="$(mktemp)"
curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
  https://dl.google.com/linux/linux_signing_key.pub -o "${TMP_KEY}"
gpg --batch --yes --dearmor < "${TMP_KEY}" > "${KEYRING}"
chmod 0644 "${KEYRING}"
rm -f "${TMP_KEY}"

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

# Register a Google Chrome desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh google-chrome.desktop
