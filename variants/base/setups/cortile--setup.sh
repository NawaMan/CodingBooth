#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# cortile--setup.sh — Cortile auto-tiling for XFCE (https://github.com/leukipp/cortile),
# installed from the release binary. Installed but NOT started by default; pass
# --enable to start it on every XFCE login (the xfce+cortile extension does).
# A user can also start it by hand with `cortile &`.
#
# Cortile writes its default config to ~/.config/cortile/config.toml on first run
# (keys: Ctrl+Shift+T toggle, Ctrl+Shift+arrows layouts, ...). Once enabled, a user
# can still turn it off in Settings → Session and Startup.
#
# Usage: cortile--setup.sh [--enable] [VERSION]
#   --enable  also start Cortile on XFCE login (/etc/xdg/autostart/cb-cortile.desktop)
#   VERSION   release version (default: 2.5.2; other versions skip checksum pinning
#             and are verified against the release's checksums.txt instead)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

ENABLE=false
if [[ "${1:-}" == "--enable" ]]; then
  ENABLE=true
  shift
fi
CORTILE_VERSION="${1:-2.5.2}"
AUTOSTART=/etc/xdg/autostart/cb-cortile.desktop

case "$(uname -m)" in
  x86_64)  ARCH="amd64"; PINNED_SHA="dcc104bb2dbdf5596b6de5e578b8988347200759ca5c1134f9d0bec3b19ef3dd" ;;
  aarch64) ARCH="arm64"; PINNED_SHA="acebab88ef9e2301a25ce754838b3e8a5f6d800312436e871f2fad73b6f6fc9a" ;;
  *) echo "❌ Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Enabling an already-installed Cortile (the variant ships it) needs no download.
# The version is recorded beside the binary: `cortile -v` means verbose and would
# start the tiler, not print a version.
VERSION_FILE=/usr/local/share/cortile/version
if [[ ! -x /usr/local/bin/cortile || "$(cat "$VERSION_FILE" 2>/dev/null)" != "$CORTILE_VERSION" ]]; then
  apt--install.sh curl ca-certificates

  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT

  TARBALL="cortile_${CORTILE_VERSION}_linux_${ARCH}.tar.gz"
  BASE_URL="https://github.com/leukipp/cortile/releases/download/v${CORTILE_VERSION}"
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "$WORK_DIR/$TARBALL" "$BASE_URL/$TARBALL"

  if [[ "$CORTILE_VERSION" == "2.5.2" ]]; then
    echo "${PINNED_SHA}  $WORK_DIR/$TARBALL" | sha256sum -c -
  else
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "$WORK_DIR/checksums.txt" "$BASE_URL/cortile_${CORTILE_VERSION}_checksums.txt"
    (cd "$WORK_DIR" && sha256sum -c --ignore-missing checksums.txt)
  fi

  tar -xzf "$WORK_DIR/$TARBALL" -C "$WORK_DIR"
  install -m 0755 "$WORK_DIR/cortile" /usr/local/bin/cortile
  install -d "$(dirname "$VERSION_FILE")"
  echo "$CORTILE_VERSION" > "$VERSION_FILE"
fi

if [[ "$ENABLE" == "true" ]]; then
  mkdir -p /etc/xdg/autostart
  cat > "$AUTOSTART" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Cortile
Comment=Auto-tiling for XFCE
Exec=/usr/local/bin/cortile
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
DESKTOP
  chmod 0644 "$AUTOSTART"
  echo "✅ Cortile ${CORTILE_VERSION} installed: /usr/local/bin/cortile (autostarts on XFCE login)"
else
  echo "✅ Cortile ${CORTILE_VERSION} installed: /usr/local/bin/cortile (not started; enable with xfce+cortile)"
fi
