#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# bismuth--setup.sh — Bismuth auto-tiling for the KDE Plasma desktop.
#
# Bismuth is a KWin script: KWin stays the window manager and Bismuth only lays
# the windows out, so plasmashell's panel, desktop and pop-ups keep working
# untouched. It installs switched off; start-bismuth / stop-bismuth turn it on
# and off in a running session. Tiling at login is bismuth-default--setup.sh;
# window gaps are bismuth-gaps--setup.sh (the bismuth template's extensions).
#
# What it sets up:
#   - kwin-bismuth from apt (APT_SNAPSHOT applies). Plasma 5.27 is the release
#     Bismuth targets; its settings page is System Settings → Window Management
#     → Window Tiling.
#   - start-bismuth / stop-bismuth — flip KWin's bismuthEnabled plugin key in
#     ~/.config/kwinrc and ask KWin to reconfigure. The choice is remembered,
#     like any other Plasma setting, until the other command is run.
#   - A "Tiling for KDE (Bismuth)" launcher (menu + desktop icon) running
#     start-bismuth, and a "Leave Tiling (Bismuth)" menu entry running
#     stop-bismuth.
#   - The shortcuts, rebound from Meta (see below) by a startup hook that writes
#     them into ~/.config/kglobalshortcutsrc before the desktop starts — only
#     the ones not already there, so a rebinding made in System Settings stays.
#   - A "Bismuth Shortcuts (Tiling)" tab in the booth Help dialog (the overlay's
#     plugins/ drop-in), present exactly when this setup ran.
#
# Every Bismuth shortcut defaults to Meta, which a desktop reached through noVNC
# in a browser rarely gets: the host OS or the browser keeps it. MOD=ctrl-alt
# (the default) moves them to Ctrl+Alt, which every browser passes on; Alt is
# no good on KDE, where it opens the application menus (Alt+F is File).
# Ctrl+Alt+T stays Konsole's, so the tile layout is Ctrl+Alt+Shift+T, and the
# Meta+Ctrl resize keys become Ctrl+Alt+Y/U/I/O (the row above h/j/k/l).
# MOD=meta keeps Bismuth's own bindings.
#
# Skips (exit 0) when KDE Plasma (kwin_x11) is not installed.
#
# Usage: bismuth--setup.sh [MOD]      MOD: ctrl-alt | meta (default: ctrl-alt)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v kwin_x11 &>/dev/null || ! command -v kwriteconfig5 &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "KDE Plasma is not installed (Bismuth is a KWin script)"
fi

case "${1:-ctrl-alt}" in
  ctrl-alt|Ctrl+Alt|ctrl+alt|CTRL-ALT)  BISMUTH_MOD=ctrl-alt ; MOD_LABEL="Ctrl+Alt" ;;
  meta|Meta|META|super|Super)           BISMUTH_MOD=meta     ; MOD_LABEL="Meta"     ;;
  *) echo "❌ Unknown mod key '${1}' (use ctrl-alt or meta)" >&2; exit 1 ;;
esac

apt--install.sh kwin-bismuth

if [[ ! -f /usr/share/kwin/scripts/bismuth/metadata.desktop ]]; then
  echo "❌ kwin-bismuth installed but the KWin script is missing" >&2
  exit 2
fi

# ---- make the packaged script loadable ----
# Ubuntu 24.04's kwin-bismuth ships a code/index.mjs bundled for ES2022: its
# classes set statics in `static { this.id = "…"; }` blocks, which Qt 5.15's
# QML engine cannot parse ("Unexpected token `{'"). KWin then loads the script
# with no code behind it, and nothing ever tiles. Every such block only assigns
# statics, so each is moved to plain assignments after its class — the same
# values, set at the same point in module evaluation. `_Name` (the class's inner
# name, in scope only inside the class) becomes `Name`.
BISMUTH_JS=/usr/share/kwin/scripts/bismuth/contents/code/index.mjs
if grep -q '^  static {' "$BISMUTH_JS"; then
  perl -e '
    my ($cls, $in, @hold);
    while (my $l = <STDIN>) {
      $cls = $1 if $l =~ /^var (\w+) = class\b/;
      if (!$in && $l =~ /^  static \{\s*$/) { $in = 1; next; }
      if ($in) {
        if ($l =~ /^  \}\s*$/) { $in = 0; next; }
        (my $s = $l) =~ s/^\s*this\./$cls./;
        $s =~ s/\b_\Q$cls\E\b/$cls/g;
        push @hold, $s;
        next;
      }
      print $l;
      if (@hold && $l =~ /^\};\s*$/) { print @hold; @hold = (); }
    }
    die "unterminated static block\n" if $in || @hold;
  ' < "$BISMUTH_JS" > "${BISMUTH_JS}.cb-tmp"
  mv "${BISMUTH_JS}.cb-tmp" "$BISMUTH_JS"
  chmod 0644 "$BISMUTH_JS"
fi
if grep -qE '^\s*static \{' "$BISMUTH_JS"; then
  echo "❌ ${BISMUTH_JS} still has ES2022 static blocks, which KWin (Qt 5) cannot load" >&2
  exit 2
fi

# ---- start-bismuth / stop-bismuth ----
# Both run as the desktop user: from the launchers (inside the session) or a
# terminal (booth exec, which has no session bus of its own — borrow
# plasmashell's).
for mode in start stop; do
  cat > "/usr/local/bin/${mode}-bismuth" <<EOF
#!/usr/bin/env bash
# ${mode}-bismuth — turn Bismuth auto-tiling $([[ $mode == start ]] && echo on || echo off) in the running KDE desktop.
# Installed by bismuth--setup.sh; $([[ $mode == start ]] && echo stop || echo start)-bismuth does the opposite.
set -u
ENABLED=$([[ $mode == start ]] && echo true || echo false)
EOF
  cat >> "/usr/local/bin/${mode}-bismuth" <<'EOF'
kwriteconfig5 --file kwinrc --group Plugins --key bismuthEnabled "$ENABLED"

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  pid="$(pgrep -u "$(id -u)" -x plasmashell | head -1)"
  if [[ -n "$pid" ]]; then
    DBUS_SESSION_BUS_ADDRESS="$(tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
    export DBUS_SESSION_BUS_ADDRESS
  fi
fi
if ! dbus-send --session --print-reply --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; then
  echo "ℹ️  No running KDE desktop: Bismuth will be $([[ $ENABLED == true ]] && echo on || echo off) when it starts."
  exit 0
fi
if [[ $ENABLED == true ]]; then
  echo "✅ Bismuth tiling is on (stop-bismuth to turn it off)."
else
  echo "✅ Bismuth tiling is off (start-bismuth to tile again)."
fi
EOF
  chmod 0755 "/usr/local/bin/${mode}-bismuth"
done

# ---- launchers: menu entries + desktop icon ----
# The package ships its own icon (hicolor apps/bismuth.svg).
cat > /usr/share/applications/cb-bismuth-start.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Tiling for KDE (Bismuth)
Comment=Turn on Bismuth auto-tiling for this desktop
Exec=start-bismuth
Icon=bismuth
Terminal=false
Categories=System;Settings;
EOF
cat > /usr/share/applications/cb-bismuth-stop.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Leave Tiling (Bismuth)
Comment=Turn off Bismuth auto-tiling for this desktop
Exec=stop-bismuth
Icon=bismuth
Terminal=false
Categories=System;Settings;
EOF
chmod 0644 /usr/share/applications/cb-bismuth-start.desktop /usr/share/applications/cb-bismuth-stop.desktop
"$SCRIPT_DIR/cb-desktop-icon.sh" /usr/share/applications/cb-bismuth-start.desktop

# ---- shortcuts ----
# KGlobalAccel reads only the user's kglobalshortcutsrc (no /etc/xdg cascade),
# and only when the session starts, so the Ctrl+Alt bindings are seeded by a
# startup hook, which runs as the user before the desktop does. Each entry is
# "active,default,name": the default stays Bismuth's Meta key, so "Default" in
# System Settings still means Bismuth's own.
STARTUP_FILE=/usr/share/startup.d/57-cb-bismuth--startup.sh
if [[ $BISMUTH_MOD == ctrl-alt ]]; then
  install -d -m 0755 /usr/share/startup.d
  cat > "$STARTUP_FILE" <<'EOF'
#!/usr/bin/env bash
# 57-cb-bismuth--startup.sh — seed Bismuth's Ctrl+Alt shortcuts into
# ~/.config/kglobalshortcutsrc. Installed by bismuth--setup.sh. Writes only the
# keys that are not there yet, so shortcuts changed in System Settings stay.
command -v kwriteconfig5 >/dev/null 2>&1 || exit 0
[[ -n "$(kreadconfig5 --file kglobalshortcutsrc --group bismuth --key _k_friendly_name 2>/dev/null)" ]] ||
  kwriteconfig5 --file kglobalshortcutsrc --group bismuth --key _k_friendly_name Bismuth || true
while IFS=';' read -r action active default name; do
  [[ -z "$action" ]] && continue
  current="$(kreadconfig5 --file kglobalshortcutsrc --group bismuth --key "$action" 2>/dev/null)"
  [[ -n "$current" ]] && continue
  # kglobalaccel reads the entry as a KConfig string list, where "\," is an
  # escaped comma: a bare backslash key (Ctrl+Alt+\) would swallow the
  # separator and the whole entry is dropped. Escape it at the list level;
  # kwriteconfig5 then escapes it again for the file.
  active="${active//\\/\\\\}"
  default="${default//\\/\\\\}"
  kwriteconfig5 --file kglobalshortcutsrc --group bismuth --key "$action" "${active},${default},${name}" || true
done <<'MAP'
focus_left_window;Ctrl+Alt+H;Meta+H;Focus Left Window
focus_bottom_window;Ctrl+Alt+J;Meta+J;Focus Bottom Window
focus_upper_window;Ctrl+Alt+K;Meta+K;Focus Upper Window
focus_right_window;Ctrl+Alt+L;Meta+L;Focus Right Window
move_window_to_left_pos;Ctrl+Alt+Shift+H;Meta+Shift+H;Move Window Left
move_window_to_bottom_pos;Ctrl+Alt+Shift+J;Meta+Shift+J;Move Window Down
move_window_to_upper_pos;Ctrl+Alt+Shift+K;Meta+Shift+K;Move Window Up
move_window_to_right_pos;Ctrl+Alt+Shift+L;Meta+Shift+L;Move Window Right
decrease_window_width;Ctrl+Alt+Y;Meta+Ctrl+H;Decrease Window Width
increase_window_height;Ctrl+Alt+U;Meta+Ctrl+J;Increase Window Height
decrease_window_height;Ctrl+Alt+I;Meta+Ctrl+K;Decrease Window Height
increase_window_width;Ctrl+Alt+O;Meta+Ctrl+L;Increase Window Width
increase_master_win_count;Ctrl+Alt+];Meta+];Increase Master Area Window Count
decrease_master_win_count;Ctrl+Alt+[;Meta+[;Decrease Master Area Window Count
toggle_window_floating;Ctrl+Alt+F;Meta+F;Toggle Active Window Floating
push_window_to_master;Ctrl+Alt+Return;Meta+Return;Push Active Window to Master Area
next_layout;Ctrl+Alt+\;Meta+\;Switch to the Next Layout
prev_layout;Ctrl+Alt+|;Meta+|;Switch to the Previous Layout
toggle_tile_layout;Ctrl+Alt+Shift+T;Meta+T;Toggle Tile Layout
toggle_monocle_layout;Ctrl+Alt+M;Meta+M;Toggle Monocle Layout
toggle_float_layout;Ctrl+Alt+Shift+F;Meta+Shift+F;Toggle Floating Layout
rotate;Ctrl+Alt+R;Meta+R;Rotate
rotate_part;Ctrl+Alt+Shift+R;Meta+Shift+R;Rotate Part
MAP
exit 0
EOF
  chmod 0755 "$STARTUP_FILE"
else
  rm -f "$STARTUP_FILE"
fi

# ---- "Bismuth Shortcuts (Tiling)" tab in the booth's Help dialog ----
# A lifecycle-panel plugin (see booth-message-wrapper--setup.sh): the wrapper
# inlines every plugins/*.js into the page, so the tab exists exactly when this
# setup ran. Skipped quietly on an image without the wrapper.
PLUGIN_DIR=/usr/local/share/booth-message-wrapper/plugins
if [[ -d "$PLUGIN_DIR" ]]; then
  if [[ $BISMUTH_MOD == ctrl-alt ]]; then
    RESIZE_KEYS="K+Y / U / I / O"
    TILE_KEY="K+Shift+T"
  else
    RESIZE_KEYS="K+Ctrl+h / j / k / l"
    TILE_KEY="K+T"
  fi
  sed -e "s/@MOD@/${MOD_LABEL}/g" -e "s|@RESIZE@|${RESIZE_KEYS}|g" -e "s|@TILE@|${TILE_KEY}|g" \
    > "$PLUGIN_DIR/bismuth-help.js" <<'EOF'
// Bismuth key bindings in the CodingBooth Help dialog. Installed by bismuth--setup.sh.
(function () {
  if (!window.BoothHelp) {
    return;
  }
  var K = "@MOD@";
  var sub = function (s) { return s.replace(/K\+/g, K + "+"); };
  var keys = [
    ["K+h / j / k / l",         "Focus left / down / up / right"],
    ["K+Shift+h / j / k / l",   "Move the window left / down / up / right"],
    ["@RESIZE@",                "Narrower / taller / shorter / wider"],
    ["K+Enter",                 "Make the window the main (master) one"],
    ["K+] / K+[",               "More / fewer windows in the master area"],
    ["K+f",                     "Float / tile the window"],
    ["K+m",                     "Monocle layout: one full-size window at a time (again to leave)"],
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
      'Shortcuts → <strong>Bismuth</strong>, where each can be changed or reset to Bismuth\'s ' +
      'own Meta key.</p>';
  window.BoothHelp.addTab("bismuth", "Bismuth Shortcuts (Tiling)",
    '<p class="msg-dialog-lead">This desktop can tile its windows with <strong>Bismuth</strong>: ' +
    'new windows split the screen instead of overlapping, driven from the keyboard with ' +
    '<strong>' + K + '</strong>. The panel, menu and desktop work as usual.</p>' +
    '<table style="border-collapse:collapse;font-size:13px">' + rows + '</table>' +
    keyNote +
    '<h3>Switching</h3>' +
    '<p>Run <code>start-bismuth</code> (or the <strong>Tiling for KDE (Bismuth)</strong> icon) ' +
    'to tile, and <code>stop-bismuth</code> (or <strong>Leave Tiling (Bismuth)</strong> in the ' +
    'menu) to stop; the choice is remembered. Layouts, gaps and window rules are in System ' +
    'Settings → Window Management → <strong>Window Tiling</strong>.</p>');
})();
EOF
  chmod 0644 "$PLUGIN_DIR/bismuth-help.js"
fi

echo "✅ Bismuth $(dpkg-query -W -f='${Version}' kwin-bismuth) installed for KDE Plasma (keys: ${MOD_LABEL})"
echo "   Switch:   start-bismuth / stop-bismuth"
echo "   Settings: System Settings → Window Management → Window Tiling"
