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

# This script will always be installed by root.
HOME=/root


export DEBIAN_FRONTEND=noninteractive

echo "🔧 Installing Firefox (Mozillateam PPA, no snap)…"

# Remove any snap-stubbed Firefox
apt-get remove -y firefox || true

# Make sure tools we need are present (some minimal images skip them).
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates gnupg

# ---- Add Mozillateam PPA *without* using add-apt-repository (which goes
# through launchpad.net's API and frequently times out) and *without* using
# `gpg --keyserver` (which needs dirmngr running and frequently fails inside
# minimal BuildKit sandboxes). Fetch the ASCII-armored key directly over
# plain HTTPS, then `gpg --dearmor` to a keyring file.
KEYRING=/etc/apt/keyrings/mozillateam-ppa.gpg
MOZILLATEAM_KEY_ID=0AB215679C571D1C8325275B9BDB3D89CE49EC21

# Detect Ubuntu codename for the apt source line
. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}"

install -d -m 0755 /etc/apt/keyrings

# HKP-over-HTTPS endpoints. These return ASCII-armored OpenPGP keys via plain
# HTTP GET — no dirmngr, no UDP, no firewalled ports. If keyserver.ubuntu.com
# is down we fall back to keys.openpgp.org.
TMP_ASC="$(mktemp)"
trap 'rm -f "$TMP_ASC"' EXIT

fetched=0
for url in \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${MOZILLATEAM_KEY_ID}" \
    "https://keys.openpgp.org/vks/v1/by-fingerprint/${MOZILLATEAM_KEY_ID}"
do
  echo "ℹ️ Fetching Mozillateam signing key from ${url%%\?*} ..."
  if curl -fsSL --max-time 30 "${url}" -o "${TMP_ASC}" && \
     [[ -s "${TMP_ASC}" ]] && \
     grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "${TMP_ASC}"; then
    fetched=1
    break
  fi
  echo "ℹ️  fetch failed, trying next source ..."
done

if [[ "${fetched}" -ne 1 ]]; then
  echo "❌ Could not fetch Mozillateam signing key from any HTTPS source" >&2
  exit 1
fi

gpg --dearmor < "${TMP_ASC}" > "${KEYRING}"
chmod 0644 "${KEYRING}"

cat >/etc/apt/sources.list.d/mozillateam-ubuntu-ppa.list <<EOF
deb [signed-by=${KEYRING}] http://ppa.launchpad.net/mozillateam/ppa/ubuntu ${CODENAME} main
EOF

tee /etc/apt/preferences.d/mozillateam-firefox >/dev/null <<'EOF'
Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

# Install Firefox (DEB)
apt-get update
apt-get install -y firefox
rm -rf /var/lib/apt/lists/*
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

# Register a Firefox desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh firefox
