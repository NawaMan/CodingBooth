#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# plank--setup.sh — Plank Reloaded dock for the XFCE desktop, Matte theme.
#
# Plank Reloaded (https://github.com/zquestz/plank-reloaded) is the maintained
# fork of Plank. It is not in Ubuntu; its author publishes a signed apt repo
# with amd64 and arm64 builds. X11 only — fine, the XFCE booth runs over
# TigerVNC/X11.
#
# What it sets up:
#   - plank-reloaded from the zquestz repo (optionally a pinned version)
#   - /usr/local/bin/cb-plank-start, launched from XFCE autostart, which on the
#     first session per home sets the Matte theme and seeds the dock launchers,
#     then execs plank. Later changes made from Plank's Preferences are kept.
#   - hide-mode 'none' as the default (always visible, reserves its space).
#   - XFCE's stock bottom panel (panel-2, a launcher bar) is dropped from the
#     panel's system default, since the dock sits in the same place. The top
#     panel is untouched. Homes that already have a panel config keep theirs.
#
# Note: the zquestz repo is not covered by APT_SNAPSHOT; pass a version to pin.
#
# Usage: plank--setup.sh [VERSION]      e.g. plank--setup.sh 0.11.121-1
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v xfce4-session &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "XFCE not installed (Plank is set up for the XFCE desktop only)"
fi

PLANK_VERSION="${1:-}"
PLANK_THEME="Matte"

# ---- apt repo (idempotent) ----
# Fetch then dearmor with --batch --yes: gpg without them prompts on /dev/tty
# when the keyring already exists, which a Docker build does not have.
install -d -m 0755 /etc/apt/keyrings
KEYRING=/etc/apt/keyrings/zquestz-archive-keyring.gpg
TMP_KEY="$(mktemp)"
curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
  https://zquestz.github.io/ppa/ubuntu/KEY.gpg -o "${TMP_KEY}"
gpg --batch --yes --dearmor < "${TMP_KEY}" > "${KEYRING}"
chmod 0644 "${KEYRING}"
rm -f "${TMP_KEY}"

cat > /etc/apt/sources.list.d/zquestz.list <<EOF
deb [signed-by=${KEYRING}] https://zquestz.github.io/ppa/ubuntu ./
EOF
chmod 0644 /etc/apt/sources.list.d/zquestz.list

apt--install.sh "plank-reloaded${PLANK_VERSION:+=${PLANK_VERSION}}"

if ! command -v plank &>/dev/null; then
  echo "❌ plank-reloaded installed but no 'plank' binary on PATH" >&2
  exit 2
fi
if [[ ! -d "/usr/share/plank/themes/${PLANK_THEME}" ]]; then
  echo "❌ Plank theme '${PLANK_THEME}' not found under /usr/share/plank/themes" >&2
  exit 2
fi

# ---- always visible (default hide mode) ----
# Stock Plank autohides ("intelligent"). With hide-mode "none" the dock stays up
# and reserves its strip of the screen, so maximized and tiled (Cortile) windows
# stop above it instead of covering it. A schema override only changes the
# default: a hide mode picked in Plank's Preferences, or with
# `booth--theme set dock-hide`, still wins.
SCHEMA_DIR=/usr/share/glib-2.0/schemas
cat > "$SCHEMA_DIR/90-cb-plank.gschema.override" <<'OVERRIDE'
[net.launchpad.plank.dock.settings]
hide-mode='none'
OVERRIDE
chmod 0644 "$SCHEMA_DIR/90-cb-plank.gschema.override"
glib-compile-schemas "$SCHEMA_DIR"

# ---- per-session starter ----
cat > /usr/local/bin/cb-plank-start <<EOF
#!/usr/bin/env bash
# cb-plank-start — start the Plank dock for this XFCE session. Installed by
# plank--setup.sh; launched from /etc/xdg/autostart/cb-plank.desktop.
#
# The first session per home seeds the theme and the launchers (marker file),
# so anything changed later from Plank's Preferences survives a restart.
set -u
PLANK_THEME="${PLANK_THEME}"
EOF
cat >> /usr/local/bin/cb-plank-start <<'EOF'
DOCK_DIR="$HOME/.config/plank/dock1"
MARKER="$DOCK_DIR/.cb-seeded"
SETTINGS="net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"

# The app's .desktop file, or nothing if it is not installed. Case-insensitive,
# since terminals register as e.g. Alacritty.desktop but are named alacritty.
app_desktop() {
  local name="$1"
  ls /usr/share/applications 2>/dev/null | grep -ix "${name}.desktop" | head -1
}

# The terminal the desktop's "open a terminal" action runs, so the dock agrees
# with default-terminal--setup.sh (per-user helpers.rc, then the system one).
terminal_desktop() {
  local term="" rc f
  for rc in "$HOME/.config/xfce4/helpers.rc" /etc/xdg/xfce4/helpers.rc; do
    term="$(sed -n 's/^TerminalEmulator=//p' "$rc" 2>/dev/null | tail -1)"
    [[ -n "$term" ]] && break
  done
  f="$([[ -n "$term" ]] && app_desktop "$term")"
  [[ -n "$f" ]] && { echo "$f"; return; }
  app_desktop xfce4-terminal
}

if [[ ! -f "$MARKER" ]]; then
  mkdir -p "$DOCK_DIR/launchers"
  items=()
  for f in \
      "$(terminal_desktop)"              \
      "$(app_desktop thunar)"            \
      "$(app_desktop google-chrome)"     \
      "$(app_desktop com.google.Chrome)" \
      "$(app_desktop firefox)"           \
      "$(app_desktop chromium)"          \
      "$(app_desktop com.microsoft.VSCode)" \
      "$(app_desktop code)"; do
    [[ -n "$f" ]] || continue
    item="${f%.desktop}.dockitem"
    # google-chrome.desktop and com.google.Chrome.desktop are the same browser.
    [[ "$f" == com.google.Chrome.desktop && " ${items[*]} " == *" google-chrome.dockitem "* ]] && continue
    [[ " ${items[*]} " == *" ${item} "* ]] && continue
    printf '[PlankDockItemPreferences]\nLauncher=file:///usr/share/applications/%s\n' "$f" \
      > "$DOCK_DIR/launchers/$item"
    items+=("$item")
  done

  list="$(printf "'%s', " "${items[@]}")"
  gsettings set "$SETTINGS" dock-items "[${list%, }]" 2>/dev/null || true
  gsettings set "$SETTINGS" theme "$PLANK_THEME"      2>/dev/null || true
  touch "$MARKER"
fi

exec plank
EOF
chmod 0755 /usr/local/bin/cb-plank-start

mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/cb-plank.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Plank dock
Exec=/usr/local/bin/cb-plank-start
OnlyShowIn=XFCE;
NoDisplay=true
EOF

# ---- drop XFCE's bottom launcher panel ----
# panel-2 in xfce4-panel's system default is the bottom launcher bar. Remove it
# from the "panels" array (the only 4-space-indented value lines; plugin-ids use
# 8) and delete its property block. Both are needed: an id left in the array
# with no block makes xfce4-panel create an empty panel-2 in its place. The
# panel's plugin entries are left as harmless orphans.
PANEL_XML=/etc/xdg/xfce4/panel/default.xml
PANEL_ID_LINE='^    <value type="int" value="2"\/>$'
if [[ -f "$PANEL_XML" ]] && grep -q '<property name="panel-2" type="empty">' "$PANEL_XML"; then
  sed -i \
    -e "/${PANEL_ID_LINE}/d" \
    -e '/^    <property name="panel-2" type="empty">$/,/^    <\/property>$/d' \
    "$PANEL_XML"
  if grep -q 'panel-2' "$PANEL_XML" || grep -q "${PANEL_ID_LINE}" "$PANEL_XML"; then
    echo "❌ Failed to remove panel-2 from ${PANEL_XML}" >&2
    exit 2
  fi
  echo "✅ Removed XFCE's bottom panel from ${PANEL_XML}"
fi

echo "✅ Plank Reloaded $(dpkg-query -W -f='${Version}' plank-reloaded) installed; theme ${PLANK_THEME}"
echo "   Starter:   /usr/local/bin/cb-plank-start"
echo "   Autostart: /etc/xdg/autostart/cb-plank.desktop"
