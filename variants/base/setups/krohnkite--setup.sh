#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

# krohnkite--setup.sh — Krohnkite auto-tiling for the KDE Plasma 6 desktop.
#
# Krohnkite is a KWin script: KWin stays the window manager and Krohnkite only
# lays the windows out, so plasmashell's panel, desktop and pop-ups keep working
# untouched. It is the Plasma 6 successor of Bismuth (Plasma 5 only, and gone
# from Ubuntu 26.04), with the same keyboard model. It installs switched off;
# start-krohnkite / stop-krohnkite turn it on and off in a running session.
# Tiling at login is krohnkite-default--setup.sh; window gaps are
# krohnkite-gaps--setup.sh (the krohnkite template's extensions).
#
# What it sets up:
#   - Krohnkite from its GitHub release (.kwinscript, a zip), pinned and
#     SHA256-verified, unpacked system-wide into /usr/share/kwin/scripts/krohnkite.
#     Its settings are in System Settings → Window Management → KWin Scripts →
#     Krohnkite (the configure button).
#   - start-krohnkite / stop-krohnkite — flip KWin's krohnkiteEnabled plugin key
#     in ~/.config/kwinrc and ask KWin to reconfigure. The choice is remembered,
#     like any other Plasma setting, until the other command is run.
#   - A "Tiling for KDE (Krohnkite)" launcher (menu + desktop icon) running
#     start-krohnkite, and a "Leave Tiling (Krohnkite)" menu entry running
#     stop-krohnkite.
#   - The shortcuts, rebound from Meta (see below) by a startup hook that writes
#     them into ~/.config/kglobalshortcutsrc before the desktop starts — only
#     the ones not already there, so a rebinding made in System Settings stays.
#   - A "Krohnkite Shortcuts (Tiling)" tab in the booth Help dialog (the
#     overlay's plugins/ drop-in), present exactly when this setup ran.
#
# Every Krohnkite shortcut defaults to Meta, which a desktop reached through
# noVNC in a browser rarely gets: the host OS or the browser keeps it. MOD=ctrl-alt
# (the default) moves them to Ctrl+Alt, which every browser passes on; Alt is
# no good on KDE, where it opens the application menus (Alt+F is File).
# Ctrl+Alt+T stays Konsole's, so the tile layout is Ctrl+Alt+Shift+T, and the
# Meta+Ctrl resize keys become Ctrl+Alt+Y/U/I/O (the row above h/j/k/l).
# MOD=meta keeps Krohnkite's own bindings.
#
# Skips (exit 0) when KDE Plasma 6 (KWin + kwriteconfig6) is not installed.
#
# Usage: krohnkite--setup.sh [MOD] [--version <ver> --sha256 <hex> [--asset <file>]]
#   MOD: ctrl-alt | meta (default: ctrl-alt)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

# ---- pinned release ----
KROHNKITE_VERSION="0.9.9.2"
KROHNKITE_ASSET="krohnkite-0.9.9.2_1d7fd74.kwinscript"
KROHNKITE_SHA256="42f7f66531d366c74b5fc860381da3517ccb4cdccd1f80c122fcab6e9a8fcf7e"

MOD_ARG=""
REQ_VER=""
REQ_SHA=""
REQ_ASSET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift || true ;;
    --sha256)  shift; REQ_SHA="${1:-}"; shift || true ;;
    --asset)   shift; REQ_ASSET="${1:-}"; shift || true ;;
    -*) echo "❌ Unknown arg: $1" >&2; exit 2 ;;
    *)
      if [[ -n "$MOD_ARG" ]]; then echo "❌ Unexpected argument: $1" >&2; exit 2; fi
      MOD_ARG="$1"; shift ;;
  esac
done

source "$SCRIPT_DIR/libs/skip-setup.sh"
if { ! command -v kwin_x11 &>/dev/null && ! command -v kwin_wayland &>/dev/null; } \
   || ! command -v kwriteconfig6 &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "KDE Plasma 6 is not installed (Krohnkite is a KWin script)"
fi

case "${MOD_ARG:-ctrl-alt}" in
  ctrl-alt|Ctrl+Alt|ctrl+alt|CTRL-ALT)  KROHNKITE_MOD=ctrl-alt ; MOD_LABEL="Ctrl+Alt" ;;
  meta|Meta|META|super|Super)           KROHNKITE_MOD=meta     ; MOD_LABEL="Meta"     ;;
  *) echo "❌ Unknown mod key '${MOD_ARG}' (use ctrl-alt or meta)" >&2; exit 1 ;;
esac

REQ_VER="${REQ_VER#v}"
if [[ -z "$REQ_VER" || "$REQ_VER" == "$KROHNKITE_VERSION" ]]; then
  VERSION="$KROHNKITE_VERSION"
  ASSET="${REQ_ASSET:-$KROHNKITE_ASSET}"
  SHA256="${REQ_SHA:-$KROHNKITE_SHA256}"
else
  if [[ -z "$REQ_SHA" ]]; then
    echo "❌ --version ${REQ_VER} needs --sha256 <hex> for its .kwinscript" >&2
    echo "   (only ${KROHNKITE_VERSION} has a checksum pinned in this script)" >&2
    exit 2
  fi
  VERSION="$REQ_VER"
  # Recent releases also attach the asset under the plain name; older ones
  # only as krohnkite-<ver>_<commit>.kwinscript — pass that with --asset.
  ASSET="${REQ_ASSET:-krohnkite.kwinscript}"
  SHA256="$REQ_SHA"
fi

# ---- download + verify + unpack ----
echo "🔧 Installing Krohnkite ${VERSION}…"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/anametologin/krohnkite/releases/download/${VERSION}/${ASSET}" \
  -o "${TMP_DIR}/krohnkite.kwinscript"
echo "${SHA256}  ${TMP_DIR}/krohnkite.kwinscript" | sha256sum -c - >/dev/null || {
  echo "❌ SHA256 mismatch for ${ASSET}" >&2
  exit 1
}

command -v unzip &>/dev/null || apt--install.sh unzip
KROHNKITE_DIR=/usr/share/kwin/scripts/krohnkite
rm -rf "$KROHNKITE_DIR"
install -d -m 0755 "$KROHNKITE_DIR"
unzip -q "${TMP_DIR}/krohnkite.kwinscript" -d "$KROHNKITE_DIR"
chmod -R u=rwX,go=rX "$KROHNKITE_DIR"
if [[ ! -f "$KROHNKITE_DIR/metadata.json" || ! -f "$KROHNKITE_DIR/contents/ui/main.qml" ]]; then
  echo "❌ ${ASSET} unpacked, but it is not a KWin script (no metadata.json / contents/ui/main.qml)" >&2
  exit 2
fi

# ---- start-krohnkite / stop-krohnkite ----
# Both run as the desktop user: from the launchers (inside the session) or a
# terminal (booth exec, which has no session bus of its own — borrow
# plasmashell's).
for mode in start stop; do
  cat > "/usr/local/bin/${mode}-krohnkite" <<EOF
#!/usr/bin/env bash
# ${mode}-krohnkite — turn Krohnkite auto-tiling $([[ $mode == start ]] && echo on || echo off) in the running KDE desktop.
# Installed by krohnkite--setup.sh; $([[ $mode == start ]] && echo stop || echo start)-krohnkite does the opposite.
set -u
ENABLED=$([[ $mode == start ]] && echo true || echo false)
EOF
  cat >> "/usr/local/bin/${mode}-krohnkite" <<'EOF'
kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled "$ENABLED"

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  pid="$(pgrep -u "$(id -u)" -x plasmashell | head -1)"
  if [[ -n "$pid" ]]; then
    DBUS_SESSION_BUS_ADDRESS="$(tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
    export DBUS_SESSION_BUS_ADDRESS
  fi
fi
if ! dbus-send --session --print-reply --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; then
  echo "ℹ️  No running KDE desktop: Krohnkite will be $([[ $ENABLED == true ]] && echo on || echo off) when it starts."
  exit 0
fi
if [[ $ENABLED == true ]]; then
  echo "✅ Krohnkite tiling is on (stop-krohnkite to turn it off)."
else
  echo "✅ Krohnkite tiling is off (start-krohnkite to tile again)."
fi
EOF
  chmod 0755 "/usr/local/bin/${mode}-krohnkite"
done

# ---- launchers: menu entries + desktop icon ----
# Krohnkite ships no icon of its own; its metadata names Breeze's tiling icon.
cat > /usr/share/applications/cb-krohnkite-start.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Tiling for KDE (Krohnkite)
Comment=Turn on Krohnkite auto-tiling for this desktop
Exec=start-krohnkite
Icon=dialog-tile-clones
Terminal=false
Categories=System;Settings;
EOF
cat > /usr/share/applications/cb-krohnkite-stop.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Leave Tiling (Krohnkite)
Comment=Turn off Krohnkite auto-tiling for this desktop
Exec=stop-krohnkite
Icon=dialog-tile-clones
Terminal=false
Categories=System;Settings;
EOF
chmod 0644 /usr/share/applications/cb-krohnkite-start.desktop /usr/share/applications/cb-krohnkite-stop.desktop
"$SCRIPT_DIR/cb-desktop-icon.sh" /usr/share/applications/cb-krohnkite-start.desktop

# ---- shortcuts ----
# KGlobalAccel reads only the user's kglobalshortcutsrc (no /etc/xdg cascade),
# and only when the session starts, so the Ctrl+Alt bindings are seeded by a
# startup hook, which runs as the user before the desktop does. KWin registers
# a script's shortcuts under its own component, so they live in the [kwin]
# group as Krohnkite<Action>. Each entry is "active,default,name": the default
# stays Krohnkite's Meta key, so "Default" in System Settings still means
# Krohnkite's own.
STARTUP_FILE=/usr/share/startup.d/57-cb-krohnkite--startup.sh
if [[ $KROHNKITE_MOD == ctrl-alt ]]; then
  install -d -m 0755 /usr/share/startup.d
  cat > "$STARTUP_FILE" <<'EOF'
#!/usr/bin/env bash
# 57-cb-krohnkite--startup.sh — seed Krohnkite's Ctrl+Alt shortcuts into
# ~/.config/kglobalshortcutsrc. Installed by krohnkite--setup.sh. Writes only
# the keys that are not there yet, so shortcuts changed in System Settings stay.
command -v kwriteconfig6 >/dev/null 2>&1 || exit 0
while IFS=';' read -r action active default name; do
  [[ -z "$action" ]] && continue
  current="$(kreadconfig6 --file kglobalshortcutsrc --group kwin --key "$action" 2>/dev/null)"
  [[ -n "$current" ]] && continue
  # kglobalaccel reads the entry as a KConfig string list, where "\," is an
  # escaped comma: a bare backslash key (Ctrl+Alt+\) would swallow the
  # separator, and a bare comma key (Ctrl+Alt+,) would split the entry — either
  # way it is dropped. Escape both at the list level; kwriteconfig6 then
  # escapes the backslashes again for the file.
  active="${active//\\/\\\\}";   active="${active//,/\\,}"
  default="${default//\\/\\\\}"; default="${default//,/\\,}"
  kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "$action" "${active},${default},${name}" || true
done <<'MAP'
KrohnkiteFocusLeft;Ctrl+Alt+H;Meta+H;Krohnkite: Focus Left
KrohnkiteFocusDown;Ctrl+Alt+J;Meta+J;Krohnkite: Focus Down
KrohnkiteFocusUp;Ctrl+Alt+K;Meta+K;Krohnkite: Focus Up
KrohnkiteFocusRight;Ctrl+Alt+L;Meta+L;Krohnkite: Focus Right
KrohnkiteFocusNext;Ctrl+Alt+.;Meta+.;Krohnkite: Focus Next
KrohnkiteFocusPrev;Ctrl+Alt+,;Meta+,;Krohnkite: Focus Previous
KrohnkiteShiftLeft;Ctrl+Alt+Shift+H;Meta+Shift+H;Krohnkite: Move Left
KrohnkiteShiftDown;Ctrl+Alt+Shift+J;Meta+Shift+J;Krohnkite: Move Down/Next
KrohnkiteShiftUp;Ctrl+Alt+Shift+K;Meta+Shift+K;Krohnkite: Move Up/Prev
KrohnkiteShiftRight;Ctrl+Alt+Shift+L;Meta+Shift+L;Krohnkite: Move Right
KrohnkiteShrinkWidth;Ctrl+Alt+Y;Meta+Ctrl+H;Krohnkite: Shrink Width
KrohnkiteGrowHeight;Ctrl+Alt+U;Meta+Ctrl+J;Krohnkite: Grow Height
KrohnkiteShrinkHeight;Ctrl+Alt+I;Meta+Ctrl+K;Krohnkite: Shrink Height
KrohnkitegrowWidth;Ctrl+Alt+O;Meta+Ctrl+L;Krohnkite: Grow Width
KrohnkiteIncrease;Ctrl+Alt+];Meta+I;Krohnkite: Increase
KrohnkiteDecrease;Ctrl+Alt+[;Meta+D;Krohnkite: Decrease
KrohnkiteToggleFloat;Ctrl+Alt+F;Meta+F;Krohnkite: Toggle Float
KrohnkiteFloatAll;Ctrl+Alt+Shift+F;Meta+Shift+F;Krohnkite: Toggle Float All
KrohnkiteSetMaster;Ctrl+Alt+Return;Meta+Return;Krohnkite: Set master
KrohnkiteNextLayout;Ctrl+Alt+\;Meta+\;Krohnkite: Next Layout
KrohnkitePreviousLayout;Ctrl+Alt+|;Meta+|;Krohnkite: Previous Layout
KrohnkiteTileLayout;Ctrl+Alt+Shift+T;Meta+T;Krohnkite: Tile Layout
KrohnkiteMonocleLayout;Ctrl+Alt+M;Meta+M;Krohnkite: Monocle Layout
KrohnkiteRotate;Ctrl+Alt+R;Meta+R;Krohnkite: Rotate
KrohnkiteRotatePart;Ctrl+Alt+Shift+R;Meta+Shift+R;Krohnkite: Rotate Part
MAP
exit 0
EOF
  chmod 0755 "$STARTUP_FILE"
else
  rm -f "$STARTUP_FILE"
fi

# ---- "Krohnkite Shortcuts (Tiling)" tab in the booth's Help dialog ----
# A lifecycle-panel plugin (see booth-message-wrapper--setup.sh): the wrapper
# inlines every plugins/*.js into the page, so the tab exists exactly when this
# setup ran. Skipped quietly on an image without the wrapper.
PLUGIN_DIR=/usr/local/share/booth-message-wrapper/plugins
if [[ -d "$PLUGIN_DIR" ]]; then
  if [[ $KROHNKITE_MOD == ctrl-alt ]]; then
    RESIZE_KEYS="K+Y / U / I / O"
    TILE_KEY="K+Shift+T"
    MASTER_KEYS="K+] / K+["
  else
    RESIZE_KEYS="K+Ctrl+h / j / k / l"
    TILE_KEY="K+T"
    MASTER_KEYS="K+i / K+d"
  fi
  sed -e "s/@MOD@/${MOD_LABEL}/g" -e "s|@RESIZE@|${RESIZE_KEYS}|g" -e "s|@TILE@|${TILE_KEY}|g" \
      -e "s|@MASTER@|${MASTER_KEYS}|g" \
    > "$PLUGIN_DIR/krohnkite-help.js" <<'EOF'
// Krohnkite key bindings in the CodingBooth Help dialog. Installed by krohnkite--setup.sh.
(function () {
  if (!window.BoothHelp) {
    return;
  }
  var K = "@MOD@";
  var sub = function (s) { return s.replace(/K\+/g, K + "+"); };
  var keys = [
    ["K+h / j / k / l",         "Focus left / down / up / right"],
    ["K+. / K+,",               "Focus the next / previous window"],
    ["K+Shift+h / j / k / l",   "Move the window left / down / up / right"],
    ["@RESIZE@",                "Narrower / taller / shorter / wider"],
    ["K+Enter",                 "Make the window the main (master) one"],
    ["@MASTER@",                "More / fewer windows in the master area"],
    ["K+f",                     "Float / tile the window"],
    ["K+m",                     "Monocle layout: one full-size window at a time"],
    ["@TILE@",                  "Back to the tile layout"],
    ["K+\\ / K+|",              "Next / previous layout (tile, monocle, columns, spiral, …)"],
    ["K+Shift+f",               "Float every window on this desktop"],
    ["K+r / K+Shift+r",         "Rotate the layout / part of it"]
  ];
  var rows = keys.map(function (k) {
    return '<tr><td style="padding:2px 12px 2px 0;white-space:nowrap"><code>' + sub(k[0]) +
      '</code></td><td style="padding:2px 0">' + k[1] + '</td></tr>';
  }).join("");
  var keyNote = K === "Meta"
    ? '<h3>Browser took the key?</h3>' +
      '<p>Meta usually belongs to your own desktop or the browser. In Chrome, turn on the ' +
      'panel\'s <strong>Full screen</strong> button, which captures the whole keyboard.</p>'
    : '<p><code>Ctrl+Alt+T</code> still opens Konsole. The shortcuts live in System Settings → ' +
      'Keyboard → Shortcuts → <strong>KWin</strong> (search "Krohnkite"), where each can be ' +
      'changed or reset to Krohnkite\'s own Meta key.</p>';
  window.BoothHelp.addTab("krohnkite", "Krohnkite Shortcuts (Tiling)",
    '<p class="msg-dialog-lead">This desktop can tile its windows with <strong>Krohnkite</strong>: ' +
    'new windows split the screen instead of overlapping, driven from the keyboard with ' +
    '<strong>' + K + '</strong>. The panel, menu and desktop work as usual.</p>' +
    '<table style="border-collapse:collapse;font-size:13px">' + rows + '</table>' +
    keyNote +
    '<h3>Switching</h3>' +
    '<p>Run <code>start-krohnkite</code> (or the <strong>Tiling for KDE (Krohnkite)</strong> icon) ' +
    'to tile, and <code>stop-krohnkite</code> (or <strong>Leave Tiling (Krohnkite)</strong> in the ' +
    'menu) to stop; the choice is remembered. Layouts, gaps and window rules are in System ' +
    'Settings → Window Management → KWin Scripts → <strong>Krohnkite</strong>.</p>');
})();
EOF
  chmod 0644 "$PLUGIN_DIR/krohnkite-help.js"
fi

echo "✅ Krohnkite ${VERSION} installed for KDE Plasma (keys: ${MOD_LABEL})"
echo "   Switch:   start-krohnkite / stop-krohnkite"
echo "   Settings: System Settings → Window Management → KWin Scripts → Krohnkite"
