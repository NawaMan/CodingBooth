#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# freelens--setup.sh — Install FreeLens (MIT-licensed Kubernetes IDE, an
# actively-maintained fork of OpenLens) from official GitHub releases (DEB),
# with a no-sandbox launcher wrapper and a pre-seeded color theme.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION] [--theme dark|light|system]

Arguments:
  VERSION           FreeLens version (default: ${FREELENS_VERSION_DEFAULT})
  --theme <value>   Color theme to pre-seed (default: dark). "system" follows
                     the desktop's own light/dark setting instead of a fixed one.

Examples:
  $0                       # default version, dark theme
  $0 1.10.3 --theme system
USAGE
}

FREELENS_VERSION_DEFAULT="1.10.3"

[[ $EUID -eq 0 ]] || { echo "❌ This script must be run as root (use sudo)" >&2; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/cb-has-desktop.sh" || { echo "ℹ️  No desktop environment; skipping FreeLens (GUI app)."; exit 0; }

FREELENS_VERSION="${FREELENS_VERSION_DEFAULT}"
FREELENS_THEME="dark"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --theme)   FREELENS_THEME="${2:-}"; shift 2 ;;
    *)         FREELENS_VERSION="$1"; shift ;;
  esac
done

case "${FREELENS_THEME}" in
  dark)   LENS_COLOR_THEME="lens-dark-theme" ;;
  light)  LENS_COLOR_THEME="lens-light-theme" ;;
  system) LENS_COLOR_THEME="system" ;;
  *) echo "❌ Unknown --theme '${FREELENS_THEME}' (use dark, light, or system)" >&2; exit 2 ;;
esac

ARCH="$(dpkg --print-architecture)"   # amd64 or arm64
DEB_NAME="Freelens-${FREELENS_VERSION}-linux-${ARCH}.deb"
DOWNLOAD_URL="https://github.com/freelensapp/freelens/releases/download/v${FREELENS_VERSION}/${DEB_NAME}"
TMP_DEB="$(mktemp /tmp/freelens.XXXXXX.deb)"

echo "• Downloading FreeLens ${FREELENS_VERSION} (${ARCH}) ..."
echo "  From: ${DOWNLOAD_URL}"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL -o "${TMP_DEB}" "${DOWNLOAD_URL}"

# Pulls in libgtk-3-0, libnss3, etc. via the package's own dependencies.
apt-get update
apt-get install -y "${TMP_DEB}"
rm -f "${TMP_DEB}"
echo "✅ FreeLens installed"

# --- no-sandbox wrapper (Electron in a container needs it — same class of
# workaround as google-chrome--setup.sh / vscode--setup.sh in this repo).
# Keeps the package's own default flags (Wayland/ozone hints); does not
# override --user-data-dir, so it stays at Electron's own default location —
# that's exactly where the theme file seeded below has to be for it to apply.
cat >/usr/local/bin/freelens <<'EOF'
#!/usr/bin/env bash
exec /opt/Freelens/freelens \
  --no-sandbox \
  --disable-gpu-compositing \
  --ozone-platform-hint=auto \
  "$@"
EOF
chmod 755 /usr/local/bin/freelens

if [[ -f /usr/share/applications/freelens.desktop ]]; then
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/freelens %U#' /usr/share/applications/freelens.desktop || true
fi

# --- pre-seed the color theme ---
# FreeLens (like the Lens/OpenLens it's forked from) persists preferences to
# <userData>/lens-user-store.json — userData is ~/.config/Freelens on Linux
# (Electron's per-app default, from the package's own productName "Freelens").
# Confirmed against the real source (packages/core/src/features/user-preferences
# and src/renderer/themes/lens-{dark,light}.injectable.ts): the stored value is
# either the literal string "system", or a theme's own id
# ("lens-dark-theme" / "lens-light-theme").
#
# /etc/skel only seeds a *new* home directory at `useradd` time, which already
# happened earlier in the base image build — writing there at this point in
# the build has no effect on the `coder` home that already exists (confirmed
# by hand: the file never showed up under ~/.config/Freelens). Written at
# container start instead (like alacritty--setup.sh's font-config seeding),
# only when absent so a later in-session theme change is never overwritten.
STARTUP_FILE="/usr/share/startup.d/70-cb-freelens--startup.sh"
install -d "$(dirname "${STARTUP_FILE}")"
cat > "${STARTUP_FILE}" <<STARTUP
#!/usr/bin/env bash
set -uo pipefail

CONF="\$HOME/.config/Freelens/lens-user-store.json"
[[ -f "\$CONF" ]] && exit 0

mkdir -p "\$(dirname "\$CONF")"
cat > "\$CONF" <<JSON
{
  "preferences": {
    "colorTheme": "${LENS_COLOR_THEME}"
  }
}
JSON
STARTUP
chmod 755 "${STARTUP_FILE}"
echo "✅ FreeLens color theme pre-seed scheduled for container start: ${FREELENS_THEME} (${LENS_COLOR_THEME})"

# Register a FreeLens desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh freelens

echo ""
echo "ℹ️ Ready to use:"
echo "   freelens"
echo "   Honors \$KUBECONFIG / ~/.kube/config, same as kubectl and k9s."
echo "   See: https://freelensapp.github.io"
