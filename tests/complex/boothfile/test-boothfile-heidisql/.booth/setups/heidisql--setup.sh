#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                    # install latest HeidiSQL
  $0 --version 12.21    # pin specific version

Notes:
- Requires a desktop variant (desktop-xfce, desktop-kde)
- Installs HeidiSQL's native Linux build via .deb package (amd64 only — see
  the arm64 note below)
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
HEIDISQL_DEFAULT_VER="12.21"   # fallback when 'latest' cannot be resolved
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
# HeidiSQL's native Linux build only ships a packaged .deb for amd64. arm64
# only has a beta "Raspberry Pi OS" QT6 tarball with no apt packaging and no
# dependency resolution — upstream itself calls the native Linux build beta
# and the arm64 build beta-of-a-beta, so this does not attempt it.
dpkgArch="$(dpkg --print-architecture)"
if [[ "$dpkgArch" == "arm64" ]]; then
  cat >&2 <<'WARN'

⚠️  HeidiSQL is not installed on arm64 — skipping.

    HeidiSQL's native Linux build only publishes a packaged .deb for amd64.
    The arm64 build is an unpackaged "Raspberry Pi OS" tarball with no
    dependency resolution, which upstream itself documents as beta of a
    build that is already beta. The rest of the booth is unaffected.

    What to use instead:
      • setup dbeaver   — DBeaver CE, arm64-friendly, same job (any RDBMS GUI).
      • setup cloudbeaver — browser-based, arch-independent.
      • HeidiSQL on your host Mac/PC, pointed at the port this booth exposes.

WARN

  if [[ -e /usr/local/bin/heidisql ]]; then
    echo "   (/usr/local/bin/heidisql already provided by another setup — left as is.)" >&2
  else
    cat >/usr/local/bin/heidisql <<'STUB'
#!/usr/bin/env bash
# Placeholder installed by heidisql--setup.sh on arm64, where HeidiSQL
# publishes no packaged Linux build. Explains itself instead of failing silently.
cat >&2 <<'MSG'
heidisql is not installed: HeidiSQL's native Linux build only ships a packaged
.deb for amd64, and this booth runs on arm64 (the default on Apple Silicon).

Use instead:
  dbeaver         — DBeaver CE, arm64-friendly     (booth config: dbeaver)
  cloudbeaver     — browser-based, arch-independent (booth config: cloudbeaver)
  HeidiSQL on your host, pointed at the port this booth exposes.
MSG
exit 127
STUB
    chmod 0755 /usr/local/bin/heidisql
  fi
  exit 0
elif [[ "$dpkgArch" != "amd64" ]]; then
  echo "❌ Unsupported arch: $dpkgArch (need amd64)"; exit 1
fi

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
DEB_URL="https://github.com/HeidiSQL/HeidiSQL/releases/download/v${VERSION}/heidisql_${VERSION}_amd64.deb"

# libqt6pas6 is a HeidiSQL dependency Ubuntu itself does not package (it lands
# in noble+1, not noble) — apt-get -f -y cannot conjure a package apt has
# never heard of. This is HeidiSQL's own documented workaround:
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

# apt-get's fallback above swallows a real failure (a moved asset, a new
# transitive dependency Ubuntu still lacks) into a silent no-op — verify the
# package actually landed instead of printing success regardless.
dpkg -s heidisql 2>/dev/null | grep -q '^Status: install ok installed' \
  || { echo "❌ HeidiSQL did not install (dpkg-status check failed)"; exit 1; }

# ---- desktop shortcut ----
cb-desktop-icon.sh heidisql.desktop

# ---- summary ----
INSTALLED_VERSION=$(dpkg -s heidisql 2>/dev/null | grep '^Version:' | cut -d' ' -f2 || echo "$VERSION")
echo ""
echo "✅ HeidiSQL installed."
echo "   Version: ${INSTALLED_VERSION}"
echo "   Launch:  heidisql (or from desktop menu)"
