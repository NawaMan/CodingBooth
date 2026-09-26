#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# sway--setup.sh — the sway tiling compositor for the Wayland desktop.
#
# sway is i3 for Wayland. On Wayland the compositor *is* the session, so sway
# does not run beside labwc the way i3 runs beside xfwm4: it replaces it.
# start-wayland reads /opt/codingbooth/wayland-compositor and starts sway
# instead of labwc; everything around it — the headless wlroots backend,
# wayvnc, noVNC, the waybar panel, the wallpaper, the terminal — stays.
# The Ctrl+Alt twins and window gaps are sway-ctrl-alt--setup.sh and
# sway-gaps--setup.sh (the sway template's extensions).
#
# What it sets up:
#   - sway from apt (APT_SNAPSHOT applies).
#   - /etc/sway/config — the i3 template's layout of keys, with waybar as the
#     bar, swaybg for the wallpaper and the booth's terminal opened at start.
#     It ends by including /etc/sway/config.d/*, where the extensions add
#     theirs. Copy it to ~/.config/sway/config to customize.
#   - /opt/codingbooth/wayland-compositor = sway. For one run, go back to labwc
#     with WAYLAND_COMPOSITOR=labwc in the booth's environment.
#   - A "sway Shortcuts (Tiling)" tab in the booth Help dialog (the overlay's
#     plugins/ drop-in), present exactly when this setup ran.
#
# The mod key defaults to Alt (Mod1): a desktop reached through noVNC in a
# browser rarely gets Super, which the host OS or browser usually keeps.
#
# Skips (exit 0) when the Wayland desktop (start-wayland) is not installed.
#
# Usage: sway--setup.sh [MOD]      MOD: alt | super | Mod1 | Mod4 (default: alt)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root" >&2
  exit 1
fi

source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! command -v start-wayland &>/dev/null; then
  skip_setup "$SCRIPT_NAME" "the Wayland desktop is not installed (sway replaces its labwc compositor)"
fi

case "${1:-alt}" in
  alt|Alt|ALT|Mod1|mod1)         SWAY_MOD=Mod1 ;;
  super|Super|SUPER|Mod4|mod4)   SWAY_MOD=Mod4 ;;
  *) echo "❌ Unknown mod key '${1}' (use alt or super)" >&2; exit 1 ;;
esac
MOD_LABEL="$([[ $SWAY_MOD == Mod1 ]] && echo Alt || echo Super)"

apt--install.sh sway

if ! command -v sway &>/dev/null; then
  echo "❌ sway installed but no 'sway' binary on PATH" >&2
  exit 2
fi

WALLPAPER=/usr/share/backgrounds/codingbooth/wallpaper.jpg
if [[ -f "$WALLPAPER" ]]; then
  WALLPAPER_LINE="output * bg ${WALLPAPER} fill"
else
  WALLPAPER_LINE="output * bg #1e2029 solid_color"
fi

# ---- sway config ----
install -d -m 0755 /etc/sway/config.d
cat > /etc/sway/config <<EOF
# sway config for the CodingBooth Wayland desktop. Installed by sway--setup.sh.
# Copy to ~/.config/sway/config to make it your own; that file wins over this one.
#
# Mod key: ${SWAY_MOD} (${MOD_LABEL}). The keys follow the i3 template's.

set \$mod ${SWAY_MOD}
# The booth's terminal (default-terminal--setup.sh pins it; foot otherwise).
set \$term x-terminal-emulator

font pango:FiraCode Nerd Font 10
floating_modifier \$mod normal
default_border pixel 2
default_floating_border normal
focus_follows_mouse no

# Colors follow the CodingBooth dark look: class border bg text indicator child_border
client.focused          #5294e2 #5294e2 #ffffff #8ab4f8 #5294e2
client.focused_inactive #3a3f4b #3a3f4b #c0c5ce #3a3f4b #3a3f4b
client.unfocused        #2b2e37 #2b2e37 #8b8f98 #2b2e37 #2b2e37
client.urgent           #e06c75 #e06c75 #ffffff #e06c75 #e06c75

${WALLPAPER_LINE}

# The panel is the same waybar as under labwc (start-wayland writes its config,
# with sway's workspaces added).
bar {
    swaybar_command waybar
}

# Open the terminal at start, as the labwc desktop does.
exec \$term

# Pieces that must float rather than tile.
for_window [app_id="wofi"]            floating enable, border none
for_window [window_role="pop-up"]     floating enable
for_window [window_type="dialog"]     floating enable
for_window [window_type="splash"]     floating enable

# ---- launch ----
bindsym \$mod+Return exec \$term
bindsym \$mod+d exec wofi --show drun
bindsym \$mod+Shift+d exec wofi --show run
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
bindsym \$mod+b splith
bindsym \$mod+v splitv
bindsym \$mod+f fullscreen toggle
bindsym \$mod+s layout stacking
bindsym \$mod+w layout tabbed
bindsym \$mod+e layout toggle split
bindsym \$mod+Shift+space floating toggle
bindsym \$mod+space focus mode_toggle
bindsym \$mod+a focus parent

# ---- workspaces ----
bindsym \$mod+1 workspace number 1
bindsym \$mod+2 workspace number 2
bindsym \$mod+3 workspace number 3
bindsym \$mod+4 workspace number 4
bindsym \$mod+5 workspace number 5
bindsym \$mod+6 workspace number 6
bindsym \$mod+7 workspace number 7
bindsym \$mod+8 workspace number 8
bindsym \$mod+9 workspace number 9
bindsym \$mod+0 workspace number 10

bindsym \$mod+Shift+1 move container to workspace number 1
bindsym \$mod+Shift+2 move container to workspace number 2
bindsym \$mod+Shift+3 move container to workspace number 3
bindsym \$mod+Shift+4 move container to workspace number 4
bindsym \$mod+Shift+5 move container to workspace number 5
bindsym \$mod+Shift+6 move container to workspace number 6
bindsym \$mod+Shift+7 move container to workspace number 7
bindsym \$mod+Shift+8 move container to workspace number 8
bindsym \$mod+Shift+9 move container to workspace number 9
bindsym \$mod+Shift+0 move container to workspace number 10

# ---- session ----
# No exit binding: leaving sway ends the booth's desktop, and the booth's own
# panel has Shut down / Restart for that.
bindsym \$mod+Shift+c reload

mode "resize" {
    bindsym h resize shrink width 10px
    bindsym j resize grow height 10px
    bindsym k resize shrink height 10px
    bindsym l resize grow width 10px
    bindsym Left resize shrink width 10px
    bindsym Down resize grow height 10px
    bindsym Up resize shrink height 10px
    bindsym Right resize grow width 10px
    bindsym Return mode "default"
    bindsym Escape mode "default"
    bindsym \$mod+r mode "default"
}
bindsym \$mod+r mode "resize"

# Extensions (sway-ctrl-alt, sway-gaps, …) add their pieces here.
include /etc/sway/config.d/*
EOF
chmod 0644 /etc/sway/config

# sway -C refuses to run, even just to validate, without an XDG_RUNTIME_DIR —
# or on a host with the Nvidia driver loaded (it reads /proc/modules, which a
# container shares), hence --unsupported-gpu, as start-wayland passes too —
# or, without the headless backend, it tries to open a real seat and TTY.
sway_check() {
  local dir rc
  dir="$(mktemp -d)"
  XDG_RUNTIME_DIR="$dir" WLR_BACKENDS=headless WLR_RENDERER=pixman \
    sway --unsupported-gpu -C -c "$1" "${@:2}"
  rc=$?
  rm -rf "$dir"
  return $rc
}
if ! sway_check /etc/sway/config >/dev/null 2>&1; then
  sway_check /etc/sway/config >&2 || true
  echo "❌ /etc/sway/config does not validate" >&2
  exit 2
fi

# ---- choose sway for start-wayland ----
install -d -m 0755 /opt/codingbooth
printf 'sway\n' > /opt/codingbooth/wayland-compositor
chmod 0644 /opt/codingbooth/wayland-compositor

# ---- "sway Shortcuts (Tiling)" tab in the booth's Help dialog ----
# A lifecycle-panel plugin (see booth-message-wrapper--setup.sh): the wrapper
# inlines every plugins/*.js into the page, so the tab exists exactly when this
# setup ran. The keys are listed with window.CB_SWAY_KEYS as the modifier when
# an earlier plugin sets it (sway-ctrl-alt--setup.sh's sway-00-ctrl-alt.js),
# else the mod key. Skipped quietly on an image without the wrapper.
PLUGIN_DIR=/usr/local/share/booth-message-wrapper/plugins
if [[ -d "$PLUGIN_DIR" ]]; then
  sed "s/@MOD@/${MOD_LABEL}/g" > "$PLUGIN_DIR/sway-help.js" <<'EOF'
// sway key bindings in the CodingBooth Help dialog. Installed by sway--setup.sh.
(function () {
  if (!window.BoothHelp) {
    return;
  }
  var K = window.CB_SWAY_KEYS || "@MOD@";
  var keys = [
    [K + "+Enter",                  "Open a terminal"],
    [K + "+d",                      "Application launcher (wofi)"],
    [K + "+Shift+d",                "Run a command (wofi)"],
    [K + "+Shift+q",                "Close the focused window"],
    [K + "+h / j / k / l",          "Focus left / down / up / right"],
    [K + "+Shift+h / j / k / l",    "Move the window left / down / up / right"],
    [K + "+b / " + K + "+v",        "Next window opens beside / below"],
    [K + "+w / s / e",              "Tabbed / stacked / split layout"],
    [K + "+f",                      "Full screen toggle"],
    [K + "+Shift+Space",            "Float / tile the window"],
    ["@MOD@+drag",                  "Move a floating window"],
    [K + "+r",                      "Resize mode (h/j/k/l or arrows, Enter to leave)"],
    [K + "+1 … 0",                  "Go to workspace 1 … 10"],
    [K + "+Shift+1 … 0",            "Send the window to workspace 1 … 10"],
    [K + "+Shift+c",                "Reload the sway config"]
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
  window.BoothHelp.addTab("sway", "sway Shortcuts (Tiling)",
    '<p class="msg-dialog-lead">This desktop runs <strong>sway</strong>, a tiling Wayland ' +
    'compositor: new windows split the screen instead of overlapping, and everything is ' +
    'driven from the keyboard with <strong>' + K + '</strong> as the modifier. The top panel ' +
    'shows the workspaces and the <strong>Apps</strong> launcher.</p>' +
    '<table style="border-collapse:collapse;font-size:13px">' + rows + '</table>' +
    keyNote +
    '<h3>Customizing</h3>' +
    '<p>Copy <code>/etc/sway/config</code> to <code>~/.config/sway/config</code>, edit it, then ' +
    'press <code>' + K + '+Shift+c</code>. To run the plain labwc desktop instead, start the ' +
    'booth with <code>--env WAYLAND_COMPOSITOR=labwc</code>.</p>');
})();
EOF
  chmod 0644 "$PLUGIN_DIR/sway-help.js"
fi

echo "✅ sway $(dpkg-query -W -f='${Version}' sway) installed for the Wayland desktop (mod: ${SWAY_MOD})"
echo "   Config:  /etc/sway/config   (override with ~/.config/sway/config)"
echo "   start-wayland now starts sway (WAYLAND_COMPOSITOR=labwc for labwc)"
