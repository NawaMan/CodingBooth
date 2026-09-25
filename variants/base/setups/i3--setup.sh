#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# i3--setup.sh — i3 tiling window manager in place of xfwm4 in the XFCE desktop.
#
# The XFCE session stays (panel, settings daemon, Thunar, notifications); only
# the window manager changes. Tiling, workspaces, and keyboard window control
# come from i3; menus, tray, and the booth's own tooling come from XFCE.
#
# What it sets up:
#   - i3-wm and suckless-tools (dmenu) from apt (APT_SNAPSHOT applies).
#   - xfce4-session's system default (Failsafe session) runs i3 instead of
#     xfwm4, and drops xfdesktop: i3 has no notion of a desktop window, so
#     xfdesktop would be tiled as an ordinary full-screen window. The wallpaper
#     is painted on the root window with hsetroot instead. Desktop icons are
#     therefore not shown under i3; the same launchers stay in the menu/dock.
#   - An "i3" tab in the booth Help dialog (the overlay's plugins/ drop-in)
#     listing the key bindings, present exactly when this setup ran.
#   - /etc/xdg/i3/config — read before the package's /etc/i3/config (which
#     would launch i3-config-wizard on first start). No i3bar: the XFCE top
#     panel is the bar. Copy it to ~/.config/i3/config to customize.
#
# The mod key defaults to Alt (Mod1): a desktop reached through noVNC in a
# browser rarely gets Super, which the host OS or browser usually keeps.
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
if ! command -v xfce4-session &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "XFCE not installed (i3 is set up as the XFCE session's window manager)"
fi

case "${1:-alt}" in
  alt|Alt|ALT|Mod1|mod1)         I3_MOD=Mod1 ;;
  super|Super|SUPER|Mod4|mod4)   I3_MOD=Mod4 ;;
  *) echo "❌ Unknown mod key '${1}' (use alt or super)" >&2; exit 1 ;;
esac

apt--install.sh i3-wm suckless-tools hsetroot

if ! command -v i3 &>/dev/null; then
  echo "❌ i3-wm installed but no 'i3' binary on PATH" >&2
  exit 2
fi

# ---- the XFCE session runs i3, not xfwm4 ----
# Client0 is the window manager; Client4 is xfdesktop (see header for why it
# goes). Removing a client means lowering Count too, or xfce4-session looks for
# a Client4 that is no longer there.
SESSION_XML=/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml
if [[ ! -f "$SESSION_XML" ]]; then
  echo "❌ ${SESSION_XML} not found" >&2
  exit 2
fi
if grep -q '<value type="string" value="xfwm4"/>' "$SESSION_XML"; then
  sed -i 's|<value type="string" value="xfwm4"/>|<value type="string" value="i3"/>|' "$SESSION_XML"
fi
if grep -q '<value type="string" value="xfdesktop"/>' "$SESSION_XML"; then
  sed -i \
    -e '/<property name="Client4_Command" type="array">/,/<property name="Client4_PerScreen"/d' \
    -e 's|<property name="Count" type="int" value="5"/>|<property name="Count" type="int" value="4"/>|' \
    "$SESSION_XML"
fi
if grep -qE 'value="(xfwm4|xfdesktop)"' "$SESSION_XML" \
   || ! grep -q '<value type="string" value="i3"/>' "$SESSION_XML" \
   || ! grep -q '<property name="Count" type="int" value="4"/>' "$SESSION_XML"; then
  echo "❌ Failed to switch ${SESSION_XML} to i3" >&2
  exit 2
fi

# ---- autostarts that assume xfdesktop ----
# xfce-set-wallpaper (xfce-wallpaper--setup.sh) waits for xfdesktop, then runs
# `xfdesktop --reload` regardless — which *starts* xfdesktop when it is not
# running, and i3 then places it as an ordinary window. cb-xfce-arrange-icons
# (xfce--setup.sh) only lays out desktop icons. Under i3 neither has a job (the
# wallpaper is hsetroot's, below), so hide both. Both are written by setups that
# run before this one (the desktop-xfce image / `setup xfce` at order 40).
for f in xfce-set-wallpaper.desktop cb-xfce-arrange-icons.desktop; do
  AUTOSTART="/etc/xdg/autostart/$f"
  [[ -f "$AUTOSTART" ]] || continue
  grep -q '^Hidden=true$' "$AUTOSTART" || echo 'Hidden=true' >> "$AUTOSTART"
done

# ---- wallpaper keeper ----
# hsetroot paints the root window once, but noVNC resizes the screen to the
# browser window after the session starts, and a resized root comes back black.
# This watches the screen size and repaints on every change. flock keeps it to
# one per display, since i3 re-runs exec_always on every restart.
WALLPAPER=/usr/share/backgrounds/codingbooth/wallpaper.jpg
cat > /usr/local/bin/cb-i3-wallpaper <<EOF
#!/usr/bin/env bash
# cb-i3-wallpaper — keep the wallpaper on the root window under i3, across
# screen resizes. Installed by i3--setup.sh; started from /etc/xdg/i3/config.
set -u
WALLPAPER="${WALLPAPER}"
EOF
cat >> /usr/local/bin/cb-i3-wallpaper <<'EOF'
exec 9>"/tmp/cb-i3-wallpaper${DISPLAY//[^0-9]/_}.lock"
flock -n 9 || exit 0

paint() {
  if [[ -f "$WALLPAPER" ]]; then
    hsetroot -fill "$WALLPAPER" >/dev/null 2>&1
  else
    hsetroot -solid '#1e2029' >/dev/null 2>&1
  fi
}

last=""
while xrandr --current >/dev/null 2>&1; do
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
# be, so Plank's default 'center' alignment (which relies on the WM centring a
# narrow window) leaves the icons at the left edge. 'fill' plus centred items
# has Plank centre them itself. Defaults only: a choice made in Plank's
# Preferences still wins. Harmless when Plank is not installed (glib ignores an
# override for a schema it does not have), and plank--setup.sh compiles it in
# if Plank comes later.
SCHEMA_DIR=/usr/share/glib-2.0/schemas
if [[ -d "$SCHEMA_DIR" ]]; then
  cat > "$SCHEMA_DIR/91-cb-plank-i3.gschema.override" <<'OVERRIDE'
[net.launchpad.plank.dock.settings]
alignment='fill'
items-alignment='center'
OVERRIDE
  chmod 0644 "$SCHEMA_DIR/91-cb-plank-i3.gschema.override"
  command -v glib-compile-schemas &>/dev/null && glib-compile-schemas "$SCHEMA_DIR"
fi

# ---- i3 config ----
install -d -m 0755 /etc/xdg/i3
cat > /etc/xdg/i3/config <<EOF
# i3 config for the CodingBooth XFCE desktop. Installed by i3--setup.sh.
# Copy to ~/.config/i3/config to make it your own; that file wins over this one.
#
# i3 manages the windows; the XFCE panel (top) stays the bar, so there is no
# i3bar here. Mod key: ${I3_MOD} ($([[ $I3_MOD == Mod1 ]] && echo Alt || echo Super)).

set \$mod ${I3_MOD}
# Every \$mod binding also works with \$alt — see "Ctrl+Alt copies" in i3--setup.sh.
set \$alt Control+Mod1

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

# A small gap between windows, and between windows and the panel/dock.
gaps inner 8

# Wallpaper: xfdesktop is not running under i3, so paint the root window, and
# again whenever noVNC resizes the screen.
exec_always --no-startup-id cb-i3-wallpaper

# XFCE pieces that must float rather than tile.
for_window [class="Xfce4-panel"]      floating enable
for_window [class="Xfce4-appfinder"]  floating enable
for_window [class="Xfce4-notifyd"]    floating enable, border none
for_window [class="Xfce4-settings-manager"] floating enable
for_window [window_role="pop-up"]     floating enable
for_window [window_type="dialog"]     floating enable
for_window [window_type="splash"]     floating enable

# ---- launch ----
# The terminal is the desktop's preferred one (default-terminal--setup.sh).
bindsym \$mod+Return exec --no-startup-id exo-open --launch TerminalEmulator
bindsym \$mod+d exec --no-startup-id dmenu_run
bindsym \$mod+Shift+d exec --no-startup-id xfce4-appfinder
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
bindsym \$mod+Shift+e exec --no-startup-id xfce4-session-logout

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
EOF
chmod 0644 /etc/xdg/i3/config

# ---- Ctrl+Alt copies ----
# Alt (and Super) combos only reach the booth in a browser that can capture the
# keyboard — the panel's Full screen button, Chromium only. Firefox keeps
# Alt+letter for its menus and Alt+arrows for Back/Forward, but passes
# Ctrl+Alt+letter/digit through. So every top-level \$mod binding gets a \$alt
# (Ctrl+Alt) twin. floating_modifier takes a single key, so dragging a floating
# window stays \$mod+drag (or drag its title bar).
awk '/^bindsym \$mod\+/ { print; sub(/\$mod\+/, "$alt+"); print; next } { print }' \
  /etc/xdg/i3/config > /etc/xdg/i3/config.tmp
mv /etc/xdg/i3/config.tmp /etc/xdg/i3/config
chmod 0644 /etc/xdg/i3/config

# XFCE's shortcut daemon grabs Ctrl+Alt+l (lock screen) and Ctrl+Alt+f (Thunar),
# which would race i3 for focus-right and full screen. Neither is useful here —
# locking an in-browser booth only hides it, and Thunar is on the dock — so drop
# them from the system default. Homes that already have a shortcuts file keep it.
SHORTCUTS_XML=/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
if [[ -f "$SHORTCUTS_XML" ]]; then
  sed -i -E '/<property name="&lt;Primary&gt;&lt;Alt&gt;[lf]" type="string"/d' "$SHORTCUTS_XML"
fi

if ! i3 -C -c /etc/xdg/i3/config >/dev/null; then
  i3 -C -c /etc/xdg/i3/config >&2 || true
  echo "❌ /etc/xdg/i3/config does not validate" >&2
  exit 2
fi

# ---- "i3" tab in the booth's Help dialog ----
# A lifecycle-panel plugin (see booth-message-wrapper--setup.sh): the wrapper
# inlines every plugins/*.js into the page, so the tab exists exactly when this
# setup ran. Skipped quietly on an image without the wrapper.
PLUGIN_DIR=/usr/local/share/booth-message-wrapper/plugins
if [[ -d "$PLUGIN_DIR" ]]; then
  MOD_LABEL="$([[ $I3_MOD == Mod1 ]] && echo Alt || echo Super)"
  sed "s/@MOD@/${MOD_LABEL}/g" > "$PLUGIN_DIR/i3-help.js" <<'EOF'
// i3 key bindings in the CodingBooth Help dialog. Installed by i3--setup.sh.
(function () {
  if (!window.BoothHelp) {
    return;
  }
  // Listed as Ctrl+Alt: it reaches the booth in every browser, where @MOD@ only
  // does when the browser lets go of it (Chrome's Full screen capture).
  var keys = [
    ["Ctrl+Alt+Enter",              "Open a terminal"],
    ["Ctrl+Alt+d",                  "Run a command (dmenu)"],
    ["Ctrl+Alt+Shift+d",            "Application finder"],
    ["Ctrl+Alt+Shift+q",            "Close the focused window"],
    ["Ctrl+Alt+h / j / k / l",      "Focus left / down / up / right"],
    ["Ctrl+Alt+Shift+h / j / k / l", "Move the window left / down / up / right"],
    ["Ctrl+Alt+b / Ctrl+Alt+v",     "Next window opens beside / below"],
    ["Ctrl+Alt+w / s / e",          "Tabbed / stacked / split layout"],
    ["Ctrl+Alt+f",                  "Full screen toggle"],
    ["Ctrl+Alt+Shift+Space",        "Float / tile the window"],
    ["@MOD@+drag",                  "Move a floating window (or drag its title bar)"],
    ["Ctrl+Alt+r",                  "Resize mode (h/j/k/l or arrows, Enter to leave)"],
    ["Ctrl+Alt+1 … 0",              "Go to workspace 1 … 10"],
    ["Ctrl+Alt+Shift+1 … 0",        "Send the window to workspace 1 … 10"],
    ["Ctrl+Alt+Shift+c",            "Reload the i3 config"]
  ];
  var rows = keys.map(function (k) {
    return '<tr><td style="padding:2px 12px 2px 0;white-space:nowrap"><code>' + k[0] +
      '</code></td><td style="padding:2px 0">' + k[1] + '</td></tr>';
  }).join("");
  window.BoothHelp.addTab("i3", "i3 Shortcuts",
    '<p class="msg-dialog-lead">This desktop uses the <strong>i3</strong> tiling window ' +
    'manager: new windows split the screen instead of overlapping, and everything is ' +
    'driven from the keyboard with <strong>Ctrl+Alt</strong> as the modifier. The XFCE ' +
    'panel and menu at the top work as usual.</p>' +
    '<table style="border-collapse:collapse;font-size:13px">' + rows + '</table>' +
    '<h3>Shorter: @MOD@ instead of Ctrl+Alt</h3>' +
    '<p>Every shortcut also works with just <strong>@MOD@</strong> (e.g. <code>@MOD@+h</code>) ' +
    'when the browser passes it on: in Chrome, turn on the panel\'s <strong>Full screen</strong> ' +
    'button, which captures the whole keyboard. Firefox keeps @MOD@ shortcuts for itself, so ' +
    'use Ctrl+Alt there. Ctrl+Alt+arrows may be taken by your own desktop; h/j/k/l always work.</p>' +
    '<p>To change bindings, copy ' +
    '<code>/etc/xdg/i3/config</code> to <code>~/.config/i3/config</code>, edit it, then ' +
    'press <code>Ctrl+Alt+Shift+c</code>.</p>');
})();
EOF
  chmod 0644 "$PLUGIN_DIR/i3-help.js"
fi

echo "✅ i3 $(dpkg-query -W -f='${Version}' i3-wm) is the XFCE session's window manager (mod: ${I3_MOD})"
echo "   Config:  /etc/xdg/i3/config   (override with ~/.config/i3/config)"
echo "   Session: ${SESSION_XML}"
