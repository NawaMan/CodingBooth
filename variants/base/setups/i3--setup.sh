#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# i3--setup.sh — the i3 tiling window manager for the XFCE or LXQt desktop.
#
# Installs i3 beside the desktop's own window manager (xfwm4 / openbox) and the
# commands to switch between them in a running session. The desktop session
# stays (panel, menu, tray, file manager, notifications); only window
# management changes. Making i3 the window manager at login is
# i3-default--setup.sh; the Ctrl+Alt twins and window gaps are
# i3-ctrl-alt--setup.sh and i3-gaps--setup.sh (the i3 template's extensions).
#
# What it sets up:
#   - i3-wm, suckless-tools (dmenu) and hsetroot from apt (APT_SNAPSHOT applies).
#   - /etc/xdg/i3/config — read before the package's /etc/i3/config (which
#     would launch i3-config-wizard on first start). No i3bar: the desktop's own
#     panel is the bar. It ends by including /etc/xdg/i3/config.d/*.conf, where
#     the extensions add theirs. Copy it to ~/.config/i3/config to customize.
#   - start-i3 / stop-i3 — switch the running desktop to i3 and back. The
#     desktop-icon program (xfdesktop / pcmanfm-qt --desktop) is stopped under
#     i3, which would otherwise tile it as an ordinary full-screen window; so no
#     desktop icons show under i3, and the wallpaper is painted with hsetroot.
#   - A "Tiling Window Manager (i3)" launcher (menu + desktop icon) running
#     start-i3, and a "Leave Tiling (i3)" menu entry running stop-i3.
#   - cb-i3-wallpaper (repaints on every noVNC resize) and cb-i3-dock (keeps a
#     Plank dock's icons centred under i3), both started from the i3 config.
#   - An "i3 Shortcuts (Tiling)" tab in the booth Help dialog (the overlay's plugins/
#     drop-in), present exactly when this setup ran.
#
# The mod key defaults to Alt (Mod1): a desktop reached through noVNC in a
# browser rarely gets Super, which the host OS or browser usually keeps.
#
# Skips (exit 0) when neither XFCE nor LXQt is installed.
#
# Usage: i3--setup.sh [MOD]      MOD: alt | super | Mod1 | Mod4 (default: alt)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if command -v xfce4-session &>/dev/null; then
  DESKTOP=xfce
elif command -v startlxqt &>/dev/null; then
  DESKTOP=lxqt
else
  skip_setup "$SCRIPT_NAME" "neither XFCE nor LXQt is installed (i3 runs inside one of them)"
fi

case "${1:-alt}" in
  alt|Alt|ALT|Mod1|mod1)         I3_MOD=Mod1 ;;
  super|Super|SUPER|Mod4|mod4)   I3_MOD=Mod4 ;;
  *) echo "❌ Unknown mod key '${1}' (use alt or super)" >&2; exit 1 ;;
esac
MOD_LABEL="$([[ $I3_MOD == Mod1 ]] && echo Alt || echo Super)"

apt--install.sh i3-wm suckless-tools hsetroot

if ! command -v i3 &>/dev/null; then
  echo "❌ i3-wm installed but no 'i3' binary on PATH" >&2
  exit 2
fi

# ---- wallpaper keeper ----
# hsetroot paints the root window once, but noVNC resizes the screen to the
# browser window after the session starts, and a resized root comes back black.
# This watches the screen size and repaints on every change. flock keeps it to
# one per display, since i3 re-runs exec_always on every restart; it exits once
# i3 is gone, so the desktop's own wallpaper takes over after stop-i3.
cat > /usr/local/bin/cb-i3-wallpaper <<'EOF'
#!/usr/bin/env bash
# cb-i3-wallpaper — keep the wallpaper on the root window under i3, across
# screen resizes. Installed by i3--setup.sh; started from /etc/xdg/i3/config.
set -u
WALLPAPER=""
for f in /usr/share/backgrounds/codingbooth/wallpaper.jpg /usr/share/backgrounds/codingbooth/wallpaper.png; do
  [[ -f "$f" ]] && { WALLPAPER="$f"; break; }
done

exec 9>"/tmp/cb-i3-wallpaper${DISPLAY//[^0-9]/_}.lock"
flock -n 9 || exit 0

paint() {
  if [[ -n "$WALLPAPER" ]]; then
    hsetroot -fill "$WALLPAPER" >/dev/null 2>&1
  else
    hsetroot -solid '#1e2029' >/dev/null 2>&1
  fi
}

last=""
while pgrep -x i3 >/dev/null && xrandr --current >/dev/null 2>&1; do
  size="$(xrandr --current 2>/dev/null | sed -n 's/.*current \([0-9]* x [0-9]*\).*/\1/p' | head -1)"
  if [[ "$size" != "$last" ]]; then
    paint
    last="$size"
  fi
  sleep 2
done
EOF
chmod 0755 /usr/local/bin/cb-i3-wallpaper

# ---- Plank under i3 ----
# i3 gives a dock window the whole bottom strip and ignores where it asks to
# be, so Plank's 'center' alignment (which relies on the WM centring a narrow
# window) leaves the icons at the left edge. 'fill' plus centred items has
# Plank centre them itself; stop-i3 puts 'center' back for the desktop's WM.
cat > /usr/local/bin/cb-i3-dock <<'EOF'
#!/usr/bin/env bash
# cb-i3-dock on|off — lay a Plank dock out for i3 (on) or a floating WM (off).
# Installed by i3--setup.sh. No-op without Plank.
set -u
command -v plank >/dev/null 2>&1 || exit 0
KEY=net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/
case "${1:-on}" in
  on)  gsettings set "$KEY" alignment fill   2>/dev/null
       gsettings set "$KEY" items-alignment center 2>/dev/null ;;
  off) gsettings set "$KEY" alignment center 2>/dev/null ;;
esac
exit 0
EOF
chmod 0755 /usr/local/bin/cb-i3-dock

# ---- start-i3 / stop-i3 ----
cat > /usr/local/bin/start-i3 <<EOF
#!/usr/bin/env bash
# start-i3 — switch the running ${DESKTOP^^} desktop to the i3 tiling window
# manager. Installed by i3--setup.sh; stop-i3 switches back.
set -u
DESKTOP=${DESKTOP}
EOF
cat >> /usr/local/bin/start-i3 <<'EOF'
export DISPLAY="${DISPLAY:-:1}"
if pgrep -x i3 >/dev/null; then
  echo "i3 is already running."
  exit 0
fi
if ! xrandr --current >/dev/null 2>&1; then
  echo "❌ No desktop on $DISPLAY — start the desktop first (start-desktop)." >&2
  exit 1
fi

# The desktop-icon program would be tiled as a full-screen window under i3.
case "$DESKTOP" in
  xfce) xfdesktop --quit >/dev/null 2>&1 || true ;;
  lxqt) pcmanfm-qt --desktop-off >/dev/null 2>&1 || true ;;
esac

setsid i3 --replace >/dev/null 2>&1 < /dev/null &
for _ in $(seq 1 20); do
  pgrep -x i3 >/dev/null && { echo "✅ i3 is running (stop-i3 to switch back)."; exit 0; }
  sleep 0.5
done
echo "❌ i3 did not start." >&2
exit 1
EOF
chmod 0755 /usr/local/bin/start-i3

cat > /usr/local/bin/stop-i3 <<EOF
#!/usr/bin/env bash
# stop-i3 — switch the running ${DESKTOP^^} desktop from i3 back to its own
# window manager, with its desktop icons. Installed by i3--setup.sh.
set -u
DESKTOP=${DESKTOP}
EOF
cat >> /usr/local/bin/stop-i3 <<'EOF'
export DISPLAY="${DISPLAY:-:1}"
if ! pgrep -x i3 >/dev/null; then
  echo "i3 is not running."
  exit 0
fi

case "$DESKTOP" in
  xfce) WM=xfwm4   ;;
  lxqt) WM=openbox ;;
esac
cb-i3-dock off
setsid "$WM" --replace >/dev/null 2>&1 < /dev/null &
for _ in $(seq 1 20); do
  pgrep -x "$WM" >/dev/null && break
  sleep 0.5
done
# i3 does not step aside for --replace; ask it to leave once the other WM is up.
pgrep -x i3 >/dev/null && i3-msg exit >/dev/null 2>&1

case "$DESKTOP" in
  xfce)
    setsid xfdesktop >/dev/null 2>&1 < /dev/null &
    [[ -x /usr/local/bin/xfce-set-wallpaper ]] && { setsid xfce-set-wallpaper >/dev/null 2>&1 < /dev/null & }
    ;;
  lxqt)
    setsid pcmanfm-qt --desktop --profile=lxqt >/dev/null 2>&1 < /dev/null &
    [[ -x /usr/local/bin/lxqt-set-wallpaper ]] && { setsid lxqt-set-wallpaper >/dev/null 2>&1 < /dev/null & }
    ;;
esac

if pgrep -x "$WM" >/dev/null; then
  echo "✅ Back on $WM (start-i3 to tile again)."
else
  echo "❌ $WM did not start." >&2
  exit 1
fi
EOF
chmod 0755 /usr/local/bin/stop-i3

# ---- launchers: menu entries + desktop icon ----
# Our own icon, in hicolor (the theme every icon theme falls back to): a stock
# name like preferences-system-windows is missing from some themes (Reversal).
install -d -m 0755 /usr/share/icons/hicolor/scalable/apps
cat > /usr/share/icons/hicolor/scalable/apps/cb-i3.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect x="2" y="2" width="60" height="60" rx="12" fill="#1f2430"/>
  <rect x="10" y="10" width="21" height="44" rx="3" fill="#5294e2"/>
  <rect x="35" y="10" width="19" height="20" rx="3" fill="#8ab4f8"/>
  <rect x="35" y="34" width="19" height="20" rx="3" fill="#8ab4f8"/>
</svg>
EOF
chmod 0644 /usr/share/icons/hicolor/scalable/apps/cb-i3.svg
command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -f -q /usr/share/icons/hicolor || true

cat > /usr/share/applications/cb-i3-start.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Tiling Window Manager (i3)
Comment=Switch this desktop to the i3 tiling window manager
Exec=start-i3
Icon=cb-i3
Terminal=false
Categories=System;Settings;
EOF
cat > /usr/share/applications/cb-i3-stop.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Leave Tiling (i3)
Comment=Switch this desktop back from i3 to its own window manager
Exec=stop-i3
Icon=cb-i3
Terminal=false
Categories=System;Settings;
EOF
chmod 0644 /usr/share/applications/cb-i3-start.desktop /usr/share/applications/cb-i3-stop.desktop
"$SCRIPT_DIR/cb-desktop-icon.sh" /usr/share/applications/cb-i3-start.desktop

# ---- i3 config ----
install -d -m 0755 /etc/xdg/i3/config.d
cat > /etc/xdg/i3/config <<EOF
# i3 config for the CodingBooth ${DESKTOP^^} desktop. Installed by i3--setup.sh.
# Copy to ~/.config/i3/config to make it your own; that file wins over this one.
#
# i3 manages the windows; the desktop's own panel stays the bar, so there is no
# i3bar here. Mod key: ${I3_MOD} (${MOD_LABEL}).

set \$mod ${I3_MOD}

font pango:FiraCode Nerd Font 10
floating_modifier \$mod
default_border pixel 2
default_floating_border normal
focus_follows_mouse no

# Colors follow the CodingBooth dark look: class border bg text indicator child_border
client.focused          #5294e2 #5294e2 #ffffff #8ab4f8 #5294e2
client.focused_inactive #3a3f4b #3a3f4b #c0c5ce #3a3f4b #3a3f4b
client.unfocused        #2b2e37 #2b2e37 #8b8f98 #2b2e37 #2b2e37
client.urgent           #e06c75 #e06c75 #ffffff #e06c75 #e06c75

# The desktop-icon program does not run under i3: paint the wallpaper on the
# root window (again whenever noVNC resizes the screen), and centre a Plank dock.
exec_always --no-startup-id cb-i3-wallpaper
exec_always --no-startup-id cb-i3-dock on

# Desktop pieces that must float rather than tile.
for_window [class="Xfce4-panel"]      floating enable
for_window [class="Xfce4-appfinder"]  floating enable
for_window [class="Xfce4-notifyd"]    floating enable, border none
for_window [class="Xfce4-settings-manager"] floating enable
for_window [class="lxqt-runner"]      floating enable, border none
for_window [class="lxqt-notificationd"] floating enable, border none
for_window [class="lxqt-config"]      floating enable
for_window [window_role="pop-up"]     floating enable
for_window [window_type="dialog"]     floating enable
for_window [window_type="splash"]     floating enable

# ---- launch ----
# The terminal is the desktop's preferred one (default-terminal--setup.sh).
bindsym \$mod+Return exec --no-startup-id $([[ $DESKTOP == xfce ]] && echo 'exo-open --launch TerminalEmulator' || echo 'x-terminal-emulator')
bindsym \$mod+d exec --no-startup-id dmenu_run
bindsym \$mod+Shift+d exec --no-startup-id $([[ $DESKTOP == xfce ]] && echo 'xfce4-appfinder' || echo 'lxqt-runner')
bindsym \$mod+Shift+q kill

# ---- focus / move (vim keys and arrows) ----
bindsym \$mod+h focus left
bindsym \$mod+j focus down
bindsym \$mod+k focus up
bindsym \$mod+l focus right
bindsym \$mod+Left focus left
bindsym \$mod+Down focus down
bindsym \$mod+Up focus up
bindsym \$mod+Right focus right

bindsym \$mod+Shift+h move left
bindsym \$mod+Shift+j move down
bindsym \$mod+Shift+k move up
bindsym \$mod+Shift+l move right
bindsym \$mod+Shift+Left move left
bindsym \$mod+Shift+Down move down
bindsym \$mod+Shift+Up move up
bindsym \$mod+Shift+Right move right

# ---- layout ----
bindsym \$mod+b split h
bindsym \$mod+v split v
bindsym \$mod+f fullscreen toggle
bindsym \$mod+s layout stacking
bindsym \$mod+w layout tabbed
bindsym \$mod+e layout toggle split
bindsym \$mod+Shift+space floating toggle
bindsym \$mod+space focus mode_toggle
bindsym \$mod+a focus parent

# ---- workspaces ----
set \$ws1 "1"
set \$ws2 "2"
set \$ws3 "3"
set \$ws4 "4"
set \$ws5 "5"
set \$ws6 "6"
set \$ws7 "7"
set \$ws8 "8"
set \$ws9 "9"
set \$ws10 "10"

bindsym \$mod+1 workspace number \$ws1
bindsym \$mod+2 workspace number \$ws2
bindsym \$mod+3 workspace number \$ws3
bindsym \$mod+4 workspace number \$ws4
bindsym \$mod+5 workspace number \$ws5
bindsym \$mod+6 workspace number \$ws6
bindsym \$mod+7 workspace number \$ws7
bindsym \$mod+8 workspace number \$ws8
bindsym \$mod+9 workspace number \$ws9
bindsym \$mod+0 workspace number \$ws10

bindsym \$mod+Shift+1 move container to workspace number \$ws1
bindsym \$mod+Shift+2 move container to workspace number \$ws2
bindsym \$mod+Shift+3 move container to workspace number \$ws3
bindsym \$mod+Shift+4 move container to workspace number \$ws4
bindsym \$mod+Shift+5 move container to workspace number \$ws5
bindsym \$mod+Shift+6 move container to workspace number \$ws6
bindsym \$mod+Shift+7 move container to workspace number \$ws7
bindsym \$mod+Shift+8 move container to workspace number \$ws8
bindsym \$mod+Shift+9 move container to workspace number \$ws9
bindsym \$mod+Shift+0 move container to workspace number \$ws10

# ---- session ----
bindsym \$mod+Shift+c reload
bindsym \$mod+Shift+r restart
# Leave tiling (back to the desktop's own window manager), not log out.
bindsym \$mod+Shift+e exec --no-startup-id stop-i3

mode "resize" {
    bindsym h resize shrink width 10 px or 10 ppt
    bindsym j resize grow height 10 px or 10 ppt
    bindsym k resize shrink height 10 px or 10 ppt
    bindsym l resize grow width 10 px or 10 ppt
    bindsym Left resize shrink width 10 px or 10 ppt
    bindsym Down resize grow height 10 px or 10 ppt
    bindsym Up resize shrink height 10 px or 10 ppt
    bindsym Right resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
    bindsym \$mod+r mode "default"
}
bindsym \$mod+r mode "resize"

# Extensions (i3-ctrl-alt, i3-gaps, …) add their pieces here.
include /etc/xdg/i3/config.d/*.conf
EOF
chmod 0644 /etc/xdg/i3/config

# The package's /etc/i3/config launches i3-config-wizard. i3 searches
# ~/.config/i3, then each $XDG_CONFIG_DIRS/i3, then /etc/i3 — and LXQt's session
# sets XDG_CONFIG_DIRS=/etc:/etc/xdg:/usr/share, so under LXQt /etc/i3/config
# is found first. Point it at ours so every search order lands on the same
# config (~/.config/i3/config still wins).
cat > /etc/i3/config <<'EOF'
# Installed by i3--setup.sh: the CodingBooth i3 config lives in /etc/xdg/i3/config.
# (This file is found first when XDG_CONFIG_DIRS lists /etc before /etc/xdg, as LXQt's does.)
include /etc/xdg/i3/config
EOF
chmod 0644 /etc/i3/config

for f in /etc/xdg/i3/config /etc/i3/config; do
  if ! i3 -C -c "$f" >/dev/null; then
    i3 -C -c "$f" >&2 || true
    echo "❌ $f does not validate" >&2
    exit 2
  fi
done

# ---- "i3 Shortcuts (Tiling)" tab in the booth's Help dialog ----
# A lifecycle-panel plugin (see booth-message-wrapper--setup.sh): the wrapper
# inlines every plugins/*.js into the page, so the tab exists exactly when this
# setup ran. The keys are listed with window.CB_I3_KEYS as the modifier when an
# earlier plugin sets it (i3-ctrl-alt--setup.sh's i3-00-ctrl-alt.js), else the
# mod key. Skipped quietly on an image without the wrapper.
PLUGIN_DIR=/usr/local/share/booth-message-wrapper/plugins
if [[ -d "$PLUGIN_DIR" ]]; then
  sed "s/@MOD@/${MOD_LABEL}/g" > "$PLUGIN_DIR/i3-help.js" <<'EOF'
// i3 key bindings in the CodingBooth Help dialog. Installed by i3--setup.sh.
(function () {
  if (!window.BoothHelp) {
    return;
  }
  var K = window.CB_I3_KEYS || "@MOD@";
  var keys = [
    [K + "+Enter",                  "Open a terminal"],
    [K + "+d",                      "Run a command (dmenu)"],
    [K + "+Shift+d",                "Application finder"],
    [K + "+Shift+q",                "Close the focused window"],
    [K + "+h / j / k / l",          "Focus left / down / up / right"],
    [K + "+Shift+h / j / k / l",    "Move the window left / down / up / right"],
    [K + "+b / " + K + "+v",        "Next window opens beside / below"],
    [K + "+w / s / e",              "Tabbed / stacked / split layout"],
    [K + "+f",                      "Full screen toggle"],
    [K + "+Shift+Space",            "Float / tile the window"],
    ["@MOD@+drag",                  "Move a floating window (or drag its title bar)"],
    [K + "+r",                      "Resize mode (h/j/k/l or arrows, Enter to leave)"],
    [K + "+1 … 0",                  "Go to workspace 1 … 10"],
    [K + "+Shift+1 … 0",            "Send the window to workspace 1 … 10"],
    [K + "+Shift+c",                "Reload the i3 config"],
    [K + "+Shift+e",                "Leave tiling (back to the desktop's own window manager)"]
  ];
  var rows = keys.map(function (k) {
    return '<tr><td style="padding:2px 12px 2px 0;white-space:nowrap"><code>' + k[0] +
      '</code></td><td style="padding:2px 0">' + k[1] + '</td></tr>';
  }).join("");
  var keyNote = K === "@MOD@"
    ? '<h3>Browser took the key?</h3>' +
      '<p>In Chrome, turn on the panel\'s <strong>Full screen</strong> button, which captures ' +
      'the whole keyboard so @MOD@ shortcuts reach the booth.</p>'
    : '<h3>Shorter: @MOD@ instead of ' + K + '</h3>' +
      '<p>Every shortcut also works with just <strong>@MOD@</strong> (e.g. <code>@MOD@+h</code>) ' +
      'when the browser passes it on: in Chrome, turn on the panel\'s <strong>Full screen</strong> ' +
      'button, which captures the whole keyboard. Firefox keeps @MOD@ shortcuts for itself, so ' +
      'use ' + K + ' there. ' + K + '+arrows may be taken by your own desktop; h/j/k/l always work.</p>';
  window.BoothHelp.addTab("i3", "i3 Shortcuts (Tiling)",
    '<p class="msg-dialog-lead">This desktop can use the <strong>i3</strong> tiling window ' +
    'manager: new windows split the screen instead of overlapping, and everything is ' +
    'driven from the keyboard with <strong>' + K + '</strong> as the modifier. The panel ' +
    'and menu work as usual.</p>' +
    '<table style="border-collapse:collapse;font-size:13px">' + rows + '</table>' +
    keyNote +
    '<h3>Switching</h3>' +
    '<p>Run <code>start-i3</code> (or the <strong>Tiling Window Manager (i3)</strong> icon) to ' +
    'tile, and <code>stop-i3</code> (or <code>' + K + '+Shift+e</code>, or <strong>Leave Tiling ' +
    '(i3)</strong> in the menu) to go back. Desktop icons are hidden while i3 runs.</p>' +
    '<p>To change bindings, copy ' +
    '<code>/etc/xdg/i3/config</code> to <code>~/.config/i3/config</code>, edit it, then ' +
    'press <code>' + K + '+Shift+c</code>.</p>');
})();
EOF
  chmod 0644 "$PLUGIN_DIR/i3-help.js"
fi

echo "✅ i3 $(dpkg-query -W -f='${Version}' i3-wm) installed for ${DESKTOP^^} (mod: ${I3_MOD})"
echo "   Config:  /etc/xdg/i3/config   (override with ~/.config/i3/config)"
echo "   Switch:  start-i3 / stop-i3"
