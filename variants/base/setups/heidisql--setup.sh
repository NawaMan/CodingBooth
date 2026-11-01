#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.3.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                    # install latest HeidiSQL
  $0 --version 12.22    # pin specific version

Notes:
- Requires a desktop variant (desktop-xfce, desktop-kde)
- Installs HeidiSQL's native Linux (Qt6) build, prebuilt (sha256-checked) from
  https://github.com/NawaMan/CodingBoothPrebuilt on amd64 and arm64, into
  /opt/heidisql/heidisql-<version>
- A version not prebuilt (yet) falls back to upstream's .deb on amd64; on arm64,
  where upstream has no package, it is skipped with a warning
- Creates a desktop shortcut
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

# ---- defaults / args ----
HEIDISQL_DEFAULT_VER="12.22"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch check ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64|arm64) ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/HeidiSQL/HeidiSQL/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    echo "⚠️  Could not resolve the latest HeidiSQL release; using ${HEIDISQL_DEFAULT_VER}."
    VERSION="$HEIDISQL_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install ----
export DEBIAN_FRONTEND=noninteractive
INSTALL_DIR="/opt/heidisql/heidisql-${VERSION}"

# The prebuilt is upstream's Qt6 build with the libQt6Pas it calls in lib/, so it
# needs only Ubuntu's Qt6 and the database client libraries, which HeidiSQL loads
# when a session uses them.
install_prebuilt() {
  SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
  if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
    SETUP_LIBS_DIR="$SCRIPT_DIR/libs"
  fi
  source "${SETUP_LIBS_DIR}/prebuilt-source.sh"
  rm -rf "$INSTALL_DIR"
  cb_prebuilt_install heidisql "$VERSION" native "$INSTALL_DIR" || return 1
  echo "• Installing HeidiSQL's runtime libraries ..."
  apt-get update
  apt-get install -y --no-install-recommends \
    libqt6widgets6 libqt6gui6 libqt6core6t64 libqt6printsupport6 qt6-qpa-plugins \
    libssl3t64 libmariadb3 libpq5 libsqlite3-0 libsybdb5 libfbclient2
  rm -rf /var/lib/apt/lists/*
  ln -sfn "${INSTALL_DIR}/heidisql" /usr/local/bin/heidisql
  install -D -m 644 "${INSTALL_DIR}/heidisql.png" /usr/share/pixmaps/heidisql.png
  # What upstream's .deb installs (package-skeleton), so menus and icons match it.
  install -d /usr/share/applications
  cat > /usr/share/applications/heidisql.desktop <<'DESKTOP'
[Desktop Entry]
Name=HeidiSQL
Comment=Powerful SQL client for everyday database work
Exec=heidisql %F
Icon=heidisql
Terminal=false
Type=Application
StartupWMClass=heidisql
Categories=Database;Development;
DESKTOP
}

install_deb() {
  DEB_URL="https://github.com/HeidiSQL/HeidiSQL/releases/download/v${VERSION}/heidisql_${VERSION}_amd64.deb"

  # libqt6pas6 is a HeidiSQL dependency Ubuntu itself does not package in the
  # version the .deb is built against -- apt-get -f -y cannot conjure it. This is
  # HeidiSQL's own documented workaround:
  # https://github.com/HeidiSQL/HeidiSQL/issues/2427
  LIBQT6PAS_VERSION="6.2.10-1"
  LIBQT6PAS_URL="https://github.com/davidbannon/libqt6pas/releases/download/v6.2.10/libqt6pas6_${LIBQT6PAS_VERSION}_amd64.deb"
  echo "• Downloading libqt6pas6 ${LIBQT6PAS_VERSION} (HeidiSQL dependency Ubuntu does not package) ..."
  LIBQT6PAS_FILE="/tmp/libqt6pas6.deb"
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "$LIBQT6PAS_FILE" "$LIBQT6PAS_URL"

  echo "• Downloading HeidiSQL ${VERSION} ..."
  DEB_FILE="/tmp/heidisql.deb"
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "$DEB_FILE" "$DEB_URL"

  echo "• Installing libqt6pas6 and HeidiSQL ..."
  apt-get update
  apt-get install -y --no-install-recommends "$LIBQT6PAS_FILE" "$DEB_FILE" || {
    # Fix broken dependencies and retry
    apt-get install -f -y --no-install-recommends
  }
  rm -f "$LIBQT6PAS_FILE" "$DEB_FILE"
  rm -rf /var/lib/apt/lists/*
}

# Upstream has no packaged arm64 build, so a version not prebuilt yet (a new
# "latest" before CodingBoothPrebuilt's weekly run) is skipped there rather than
# failing the booth; a stub command says why.
skip_arm64() {
  cat >&2 <<WARN

⚠️  HeidiSQL ${VERSION} is not prebuilt for arm64 yet — skipping.

    Upstream publishes no packaged arm64 build. Pin a prebuilt version
    (--version ${HEIDISQL_DEFAULT_VER}), or use dbeaver or cloudbeaver instead.

WARN
  if [[ ! -e /usr/local/bin/heidisql ]]; then
    cat >/usr/local/bin/heidisql <<STUB
#!/usr/bin/env bash
# Placeholder installed by heidisql--setup.sh on arm64 for a version with no prebuilt.
echo "heidisql is not installed: HeidiSQL ${VERSION} has no arm64 build. Pin ${HEIDISQL_DEFAULT_VER}, or use dbeaver or cloudbeaver." >&2
exit 127
STUB
    chmod 0755 /usr/local/bin/heidisql
  fi
  exit 0
}

if install_prebuilt; then
  :
elif [[ "$dpkgArch" == amd64 ]]; then
  install_deb
else
  skip_arm64
fi

# apt-get's fallback above swallows a real failure (a moved asset, a new
# transitive dependency Ubuntu still lacks) into a silent no-op — verify the
# executable actually landed instead of printing success regardless.
[[ -x "$(readlink -f "$(command -v heidisql || true)")" ]] \
  || { echo "❌ HeidiSQL did not install (no heidisql executable)"; exit 1; }

# ---- desktop shortcut ----
cb-desktop-icon.sh heidisql.desktop

# ---- summary ----
echo ""
echo "✅ HeidiSQL installed."
echo "   Version: ${VERSION}"
echo "   Launch:  heidisql (or from desktop menu)"
