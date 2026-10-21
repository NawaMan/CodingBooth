#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# pinentry--setup.sh [--flavor auto|gtk2|qt|gnome3] — a graphical pinentry
# for the booth's desktop, so gpg (and EnvFolio / pass on top of it) asks for
# a key's passphrase in a dialog instead of inside the terminal.
#
# Every image already has pinentry-curses (gnupg -> gpg-agent depends on it),
# which is all a non-desktop booth can use, so this skips there. On a desktop
# it installs the flavour that fits and pins /usr/bin/pinentry to it: auto
# mode would otherwise pick by priority, and LXQt already carries
# pinentry-gnome3 through gnome-keyring.
#
#   auto    Qt desktops (KDE, LXQt) and Wayland compositors (labwc, sway) -> qt
#           everything else (XFCE, i3, plain X)                           -> gtk2
#
# gpg-agent runs whichever /usr/bin/pinentry points at with the caller's
# DISPLAY. With no display (a Console UI / ttyd tab) the gtk2 and qt builds
# fall back to curses, so a terminal still gets its prompt.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: pinentry--setup.sh [--flavor auto|gtk2|qt|gnome3]

  --flavor auto    pick by the desktop in this image (default)
  --flavor gtk2    pinentry-gtk2  (fits XFCE, i3 and other X11 desktops)
  --flavor qt      pinentry-qt    (fits KDE, LXQt and Wayland compositors)
  --flavor gnome3  pinentry-gnome3 (needs a gcr prompter on D-Bus)

Examples:
  pinentry--setup.sh
  pinentry--setup.sh --flavor qt
EOF
}

FLAVOR="auto"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --flavor)  FLAVOR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

# A copy in a project's .booth/setups/ shadows the image's script but brings no libs/
# with it, so fall back to the image's helpers (same convention as
# buf-code-extension--setup.sh).
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
if [[ -r "$SCRIPT_DIR/libs/skip-setup.sh" ]]; then
  source "$SCRIPT_DIR/libs/skip-setup.sh"
else
  source "${SETUP_LIBS_DIR}/skip-setup.sh"
fi

CB_HAS_DESKTOP="$SCRIPT_DIR/cb-has-desktop.sh"
[[ -x "$CB_HAS_DESKTOP" ]] || CB_HAS_DESKTOP=/opt/codingbooth/setups/cb-has-desktop.sh
if ! "$CB_HAS_DESKTOP"; then
  skip_setup "$SCRIPT_NAME" "desktop environment not available (pinentry-curses already serves the terminal)"
fi

if [[ "$FLAVOR" == "auto" ]]; then
  FLAVOR="gtk2"
  for session in startplasma-x11 plasmashell lxqt-session labwc sway wayfire; do
    if command -v "$session" >/dev/null 2>&1; then
      FLAVOR="qt"
      break
    fi
  done
fi

case "$FLAVOR" in
  gtk2)   PACKAGE="pinentry-gtk2";   PINENTRY_BIN="/usr/bin/pinentry-gtk-2"  ;;
  qt)     PACKAGE="pinentry-qt";     PINENTRY_BIN="/usr/bin/pinentry-qt"     ;;
  gnome3) PACKAGE="pinentry-gnome3"; PINENTRY_BIN="/usr/bin/pinentry-gnome3" ;;
  *) echo "❌ Unknown flavor '$FLAVOR' (auto|gtk2|qt|gnome3)" >&2; exit 1 ;;
esac

echo "🔧 Installing ${PACKAGE}…"
apt--install.sh "$PACKAGE"

update-alternatives --set pinentry "$PINENTRY_BIN"

echo "✅ ${PACKAGE} installed."
echo "   /usr/bin/pinentry -> $(readlink -f /usr/bin/pinentry)"
cat <<'EOF'
ℹ️ Ready to use — run gpg from a terminal on the desktop and the passphrase
   prompt opens as a dialog:
     folio secret show <path>
     gpgconf --kill gpg-agent    # if an agent from before was still running
   A Console UI tab has no display, so it keeps the in-terminal prompt.
EOF
