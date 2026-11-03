#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# Pharo Smalltalk setup — the Pharo VM and a fresh image from files.pharo.org.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <N>]

Examples:
  $0                  # Pharo 14
  $0 --version 13     # Pharo 13

Notes:
- Installs the VM and a pristine image under /opt/pharo/pharo-<N>, linked at /opt/pharo-stable
- 'pharo' runs headless; each user gets a writable copy of the image on first use
  (~/.local/share/pharo/<N>, or \$PHARO_IMAGE_DIR)
- 'pharo-ui' opens the Pharo IDE window — needs a desktop variant
- x86_64 only: files.pharo.org publishes no Linux arm64 VM recent enough for Pharo 12+
- The files are the release's current 'stable' builds, so they move between rebuilds;
  the sha256 of each download is printed below and recorded in /opt/pharo/pharo-<N>/SHA256SUMS
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_DIR="$(dirname "$0")"

# ---- defaults / args ----
PHARO_DEFAULT=14
REQ_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$REQ_VER" == "latest" ]] && REQ_VER=""
PHARO_VER="${REQ_VER:-$PHARO_DEFAULT}"
PHARO_VER="${PHARO_VER%%.*}"                      # 14.0 → 14
[[ "$PHARO_VER" =~ ^[0-9]+$ ]] || { echo "❌ Bad version: $PHARO_VER (want a major like 14)" >&2; exit 2; }
FILES_URL="https://files.pharo.org/get-files/${PHARO_VER}0"

# ---- arch check ----
dpkgArch="$(dpkg --print-architecture)"
if [[ "$dpkgArch" == "arm64" ]]; then
  cat >&2 <<'WARN'

⚠️  Pharo is not installed on arm64 — skipping.

    files.pharo.org publishes Linux arm64 VMs only up to 10.x, which cannot
    run Pharo 12 and later images. The rest of the booth is unaffected.

    What to use instead:
      • Pharo on your host Mac (the macOS arm64 VM is current).
      • An amd64 booth (--platform linux/amd64), at emulation speed.

WARN
  if [[ ! -e /usr/local/bin/pharo ]]; then
    cat >/usr/local/bin/pharo <<'STUB'
#!/usr/bin/env bash
# Placeholder installed by pharo--setup.sh on arm64, where no current Pharo VM exists.
echo "pharo is not installed: files.pharo.org has no Linux arm64 VM for Pharo 12+." >&2
exit 127
STUB
    chmod 0755 /usr/local/bin/pharo
  fi
  exit 0
elif [[ "$dpkgArch" != "amd64" ]]; then
  echo "❌ Unsupported arch: $dpkgArch (need amd64)"; exit 1
fi

# ---- dirs ----
INSTALL_PARENT=/opt/pharo
TARGET_DIR="${INSTALL_PARENT}/pharo-${PHARO_VER}"
LINK_DIR=/opt/pharo-stable
BIN_DIR=/usr/local/bin

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---- download ----
VM_ZIP="pharo-vm-Linux-x86_64-stable.zip"
IMAGE_ZIP="pharoImage-x86_64.zip"
echo "📦 Downloading Pharo ${PHARO_VER} VM and image ..."
curl -fsSL --retry 3 -o "$TMP_DIR/vm.zip"    "${FILES_URL}/${VM_ZIP}"    \
  || { echo "❌ No Pharo ${PHARO_VER} VM at ${FILES_URL}/${VM_ZIP}" >&2; exit 1; }
curl -fsSL --retry 3 -o "$TMP_DIR/image.zip" "${FILES_URL}/${IMAGE_ZIP}" \
  || { echo "❌ No Pharo ${PHARO_VER} image at ${FILES_URL}/${IMAGE_ZIP}" >&2; exit 1; }

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR/vm" "$TARGET_DIR/image"
unzip -q "$TMP_DIR/vm.zip"    -d "$TARGET_DIR/vm"
unzip -q "$TMP_DIR/image.zip" -d "$TMP_DIR/image"

# A stable name for the image and its changes file. The .sources file keeps its
# own name: the image refers to it by that name.
mv "$TMP_DIR"/image/*.image   "$TARGET_DIR/image/Pharo.image"
mv "$TMP_DIR"/image/*.changes "$TARGET_DIR/image/Pharo.changes"
mv "$TMP_DIR"/image/*.sources "$TARGET_DIR/image/"
[[ -f "$TMP_DIR/image/pharo.version" ]] && mv "$TMP_DIR/image/pharo.version" "$TARGET_DIR/image/"

( cd "$TMP_DIR" && sha256sum vm.zip image.zip ) | tee "$TARGET_DIR/SHA256SUMS"
chmod -R a+rX "$TARGET_DIR"

ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- starters ----
# 'pharo' (headless) and 'pharo-ui' share one script; each user runs a private
# copy of the pristine image, made on first use.
export PHARO_VER
envsubst '$PHARO_VER' >"$BIN_DIR/pharo" <<'EOF_STARTER'
#!/bin/sh
# Pharo starter — installed by pharo--setup.sh
: "${PHARO_HOME:=/opt/pharo-stable}"
: "${PHARO_IMAGE_DIR:=$HOME/.local/share/pharo/$PHARO_VER}"
if [ ! -f "$PHARO_IMAGE_DIR/Pharo.image" ]; then
  mkdir -p "$PHARO_IMAGE_DIR"
  cp "$PHARO_HOME"/image/* "$PHARO_IMAGE_DIR"/
  chmod u+w "$PHARO_IMAGE_DIR"/*
fi
case "$(basename "$0")" in
  pharo-ui) exec "$PHARO_HOME/vm/pharo" "$PHARO_IMAGE_DIR/Pharo.image" "$@" ;;
  *)        exec "$PHARO_HOME/vm/pharo" --headless "$PHARO_IMAGE_DIR/Pharo.image" "$@" ;;
esac
EOF_STARTER
chmod 0755 "$BIN_DIR/pharo"
ln -sfn "$BIN_DIR/pharo" "$BIN_DIR/pharo-ui"

# ---- desktop launcher ----
if "$SCRIPT_DIR/cb-has-desktop.sh"; then
  cat >/usr/share/applications/pharo.desktop <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Pharo
Comment=Pharo Smalltalk IDE
Exec=pharo-ui
Icon=applications-development
Terminal=false
Categories=Development;IDE;
EOF_DESKTOP
  "$SCRIPT_DIR/cb-desktop-icon.sh" pharo.desktop
fi

# ---- summary ----
echo "✅ Pharo ${PHARO_VER} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   pharo --version → "; "$TARGET_DIR/vm/pharo" --version 2>&1 | head -n1 || true

cat <<'EON'
ℹ️ Ready to use:
- pharo eval "(1 to: 10) inject: 0 into: [:a :b | a + b]"
- pharo st --quit hello.st          # run a Smalltalk script
- pharo-ui                          # the Pharo IDE (desktop variants)
EON
