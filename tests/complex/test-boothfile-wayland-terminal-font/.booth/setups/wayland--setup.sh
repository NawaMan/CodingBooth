#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# wayland--setup.sh — root-only installer for a Wayland-native desktop (labwc) streamed
# to the browser over VNC/noVNC.
#
# Pipeline (validated end-to-end; see docs/BOOTH_VARIANTS.md):
#   labwc (wlroots compositor, headless backend, software render)
#     -> wayvnc (wlr-screencopy -> RFB)
#       -> websockify + noVNC  (RFB over the single booth TCP port)
#         -> browser
#
# Unlike GNOME/mutter (not wlroots), wlroots' screencopy reliably emits frames from a
# headless session, and the headless backend needs no logind/seat. Existing X11 apps
# (Firefox/Chrome/VS Code) run via Xwayland.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi
HOME=/root

DEFAULT_GEOMETRY="${DEFAULT_GEOMETRY:-1280x800}"
DEFAULT_NOVNC_PORT="${DEFAULT_NOVNC_PORT:-10000}"
DEFAULT_VNC_PORT="${DEFAULT_VNC_PORT:-5900}"

PROFILE_FILE="/etc/profile.d/55-cb-desktop-wayland--profile.sh"
STARTER_FILE="/usr/local/bin/start-wayland"
DESKTOP_FILE="/usr/local/bin/start-desktop"
SETUPS_DIR=${SETUPS_DIR:-/opt/codingbooth/setups}

# Python for shared desktop bits (kernels etc.), mirrors the other desktop setups.
PY_VERSION=${1:-3.12}
"${SETUPS_DIR}/python--setup.sh" "${PY_VERSION}"
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
apt-get update

# --- Wayland compositor + VNC bridge + a small shell (panel/launcher/terminal) ---
apt-get install -y --no-install-recommends \
  labwc               \
  wayvnc              \
  wlr-randr           \
  xwayland            \
  swaybg              \
  waybar              \
  wofi                \
  foot                \
  novnc               \
  websockify          \
  dbus-x11            \
  x11-xserver-utils   \
  fonts-dejavu-core   \
  locales

apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- install Fira Code Nerd Font (for foot) ----
fira-code-nerd-font--setup.sh

if [[ ! -d /usr/share/novnc ]]; then
  echo "❌ /usr/share/novnc not found" >&2
  exit 2
fi

# --- noVNC autoconnect entrypoint (same UX as the X11 desktop variants) ---
cat >/usr/share/novnc/index.html <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8" /><title>noVNC</title>
<meta http-equiv="Cache-Control" content="no-store" /></head>
<body><script>
  const host = location.hostname || 'localhost';
  const port = location.port || '6080';
  const params = new URLSearchParams({ autoconnect: '1', host, port, path: 'websockify', resize: 'remote' });
  location.replace('vnc.html?' + params.toString());
</script></body></html>
HTML

# --- profile snippet ---
cat > "${PROFILE_FILE}" <<EOF
# labwc (Wayland) over VNC/noVNC defaults
export GEOMETRY=\${GEOMETRY:-${DEFAULT_GEOMETRY}}
export NOVNC_PORT=\${NOVNC_PORT:-${DEFAULT_NOVNC_PORT}}
export VNC_PORT=\${VNC_PORT:-${DEFAULT_VNC_PORT}}
export XDG_SESSION_TYPE=wayland
alias desktop-start='start-wayland'
EOF
chmod 0644 "${PROFILE_FILE}"

# --- start-wayland (foreground; Ctrl+C to stop) ---
cat > "${STARTER_FILE}" <<'EOF'
#!/usr/bin/env bash
# start-wayland — headless labwc (Wayland) -> wayvnc -> noVNC. Foreground; Ctrl+C stops.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

: "${GEOMETRY:=1280x800}"
: "${NOVNC_PORT:=10000}"
: "${VNC_PORT:=5900}"
# Chosen by default-terminal--setup.sh ("<terminal>+default"). Read from its file
# rather than only the environment: the wrapped launch (booth-entry -> runuser,
# no login shell) never sources /etc/profile.d.
if [[ -z "${DEFAULT_TERMINAL:-}" && -r /opt/codingbooth/default-terminal ]]; then
  DEFAULT_TERMINAL="$(tr -d ' \t\r\n' < /opt/codingbooth/default-terminal)"
fi
: "${DEFAULT_TERMINAL:=foot}"
# The compositor: labwc, unless a setup chose another by writing its name to
# /opt/codingbooth/wayland-compositor (sway--setup.sh writes "sway"). Read from
# a file for the same reason as the terminal above. WAYLAND_COMPOSITOR in the
# environment overrides it for one run (e.g. --env WAYLAND_COMPOSITOR=labwc).
if [[ -z "${WAYLAND_COMPOSITOR:-}" && -r /opt/codingbooth/wayland-compositor ]]; then
  WAYLAND_COMPOSITOR="$(tr -d ' \t\r\n' < /opt/codingbooth/wayland-compositor)"
fi
: "${WAYLAND_COMPOSITOR:=labwc}"
case "$WAYLAND_COMPOSITOR" in
  labwc|sway) ;;
  *) echo "❌ Unknown WAYLAND_COMPOSITOR '${WAYLAND_COMPOSITOR}' (labwc or sway)" >&2; exit 1 ;;
esac
if ! command -v "$WAYLAND_COMPOSITOR" >/dev/null 2>&1; then
  echo "❌ ${WAYLAND_COMPOSITOR} is not installed" >&2
  exit 1
fi
: "${HOME:?HOME must be set and writable}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
# wlroots headless backend: software render (no GPU), one virtual output, no seat/DRM.
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1
export XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-0
export XDG_CURRENT_DESKTOP="$WAYLAND_COMPOSITOR"

WALL=/usr/share/backgrounds/codingbooth/wallpaper.jpg

# foot default font — seeded once. Only writing it when the file is still
# absent means a later font change made by hand is never overwritten on the
# next session.
FOOT_INI="$HOME/.config/foot/foot.ini"
if [[ ! -f "$FOOT_INI" ]]; then
  mkdir -p "$(dirname "$FOOT_INI")"
  cat > "$FOOT_INI" <<'INIEOF'
[main]
font=FiraCode Nerd Font Mono:size=11
INIEOF
fi

# labwc config: autostart the shell bits + a right-click menu with the common apps.
mkdir -p "$HOME/.config/labwc"
cat > "$HOME/.config/labwc/autostart" <<AUTO
[ -f "$WALL" ] && swaybg -i "$WALL" -m fill &
waybar &
${DEFAULT_TERMINAL} &
AUTO
# minimal waybar (panel): the wofi app-launcher button plus one pinned launcher
# button per registered desktop app. labwc/swaybg draws no desktop-icon surface,
# so these panel buttons are the Wayland equivalent of a desktop icon.
mkdir -p "$HOME/.config/waybar"

# The app set is /etc/skel/Desktop — the same registry that seeds ~/Desktop on
# the icon-based desktops, populated by cb-desktop-icon.sh at build time. Each
# launcher becomes a button (label = its Name=, click runs its Exec), so the
# panel automatically tracks whatever GUI apps the booth selected.
_reg_dir=/etc/skel/Desktop
_modules='"custom/apps"'
# Under sway, the workspaces and the current binding mode (resize) lead the panel.
[[ "$WAYLAND_COMPOSITOR" == sway ]] && _modules='"sway/workspaces", "sway/mode", '"${_modules}"
_defs='"custom/apps": { "format": "  Apps", "on-click": "wofi --show drun", "tooltip": false }'
_style=""
_idx=0
shopt -s nullglob
for _f in "$_reg_dir"/*.desktop; do
  _id="$(basename "$_f" .desktop)"
  _label="$(sed -n 's/^Name=//p' "$_f" | head -1)"
  [ -n "$_label" ] || _label="$_id"
  # Launch straight from the launcher's Exec (field codes stripped) — the Wayland
  # image ships no gtk-launch/gio, so we run the command directly via sh -c.
  _exec="$(sed -n 's/^Exec=//p' "$_f" | head -1 | sed 's/%[a-zA-Z]//g; s/  */ /g; s/ *$//')"
  [ -n "$_exec" ] || continue
  # JSON-escape backslashes then double-quotes in label and command.
  _label="${_label//\\/\\\\}"; _label="${_label//\"/\\\"}"
  _exec="${_exec//\\/\\\\}"; _exec="${_exec//\"/\\\"}"
  _key="app${_idx}"; _idx=$((_idx + 1))
  _modules="${_modules}, \"custom/${_key}\""
  _defs="${_defs},
  \"custom/${_key}\": { \"format\": \"${_label}\", \"on-click\": \"${_exec}\", \"tooltip\": false }"
  _style="${_style}#custom-${_key} { padding: 0 12px; }
"
done
shopt -u nullglob
# sway's workspace buttons would take GTK's default button look — dark text on
# the dark bar — so give them the panel's colors, the focused one highlighted.
if [[ "$WAYLAND_COMPOSITOR" == sway ]]; then
  _style="${_style}#workspaces button { padding: 0 8px; color: #e6edf3; background: transparent; border: none; border-radius: 0; box-shadow: none; }
#workspaces button.focused { background: #5294e2; color: #ffffff; }
#workspaces button.urgent { background: #e06c75; color: #ffffff; }
#mode { padding: 0 10px; background: #e06c75; color: #ffffff; }
"
fi

cat > "$HOME/.config/waybar/config.jsonc" <<BAR
{
  "layer": "top", "position": "top", "height": 28,
  "modules-left": [${_modules}],
  "modules-center": ["clock"],
  "modules-right": ["tray"],
  ${_defs},
  "clock": { "format": "{:%a %d %b  %H:%M}" }
}
BAR
cat > "$HOME/.config/waybar/style.css" <<CSS
* { font-family: DejaVu Sans, sans-serif; font-size: 12px; }
window#waybar { background: #22303c; color: #e6edf3; }
#custom-apps { padding: 0 12px; }
${_style}#clock { padding: 0 12px; }
CSS

cat > "$HOME/.config/labwc/menu.xml" <<MENU
<?xml version="1.0"?>
<openbox_menu>
  <menu id="root-menu" label="CodingBooth">
    <item label="Terminal"><action name="Execute"><command>${DEFAULT_TERMINAL}</command></action></item>
    <item label="App Launcher"><action name="Execute"><command>wofi --show drun</command></action></item>
    <item label="Firefox"><action name="Execute"><command>firefox</command></action></item>
    <item label="Google Chrome"><action name="Execute"><command>google-chrome</command></action></item>
    <item label="VS Code"><action name="Execute"><command>code</command></action></item>
    <separator/>
    <item label="Reconfigure"><action name="Reconfigure"/></item>
    <item label="Exit"><action name="Exit"/></item>
  </menu>
</openbox_menu>
MENU

# rc.xml: labwc's built-in keybinds (kept via <default/>) hardcode Super+Enter to
# alacritty, whatever is installed; point it at the booth's terminal instead.
# Regenerated only while it still carries the marker, so an rc.xml you write
# (or this one with the marker line removed) is left alone.
RC_XML="$HOME/.config/labwc/rc.xml"
if [[ ! -f "$RC_XML" ]] || grep -q "cb-generated" "$RC_XML"; then
  cat > "$RC_XML" <<RC
<?xml version="1.0"?>
<!-- cb-generated by start-wayland: remove this line to keep your own edits -->
<labwc_config>
  <keyboard>
    <default />
    <keybind key="W-Return"><action name="Execute" command="${DEFAULT_TERMINAL}" /></keybind>
  </keyboard>
</labwc_config>
RC
fi

# 1) headless compositor (labwc, or sway when chosen; sway's config starts
#    swaybg/waybar/the terminal itself, as labwc's autostart above does).
#    sway refuses to start when it sees the Nvidia driver in /proc/modules —
#    which a container shares with its host — though it renders in software
#    here and never touches the GPU; --unsupported-gpu lets it through.
COMPOSITOR_ARGS=()
if [[ "$WAYLAND_COMPOSITOR" == sway ]]; then
  COMPOSITOR_ARGS=(--unsupported-gpu)
  # A restarted booth keeps /tmp: drop a previous session's sockets so the
  # wait below cannot pick one up before sway has made its own.
  pgrep -x sway >/dev/null || rm -f "$XDG_RUNTIME_DIR"/wayland-[0-9]*
fi
"$WAYLAND_COMPOSITOR" "${COMPOSITOR_ARGS[@]}" >"/tmp/cb-${WAYLAND_COMPOSITOR}.log" 2>&1 &
COMPOSITOR_PID=$!
if [[ "$WAYLAND_COMPOSITOR" == sway ]]; then
  # sway names its socket wayland-1 here, not wayland-0 as labwc does: follow
  # the one it makes (the newest), so wlr-randr and wayvnc below attach to it.
  for i in $(seq 1 30); do
    _sock="$(cd "$XDG_RUNTIME_DIR" && ls -1t 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1 || true)"
    [[ -n "$_sock" ]] && pgrep -x sway >/dev/null && break
    sleep 1
  done
  [[ -n "$_sock" ]] && export WAYLAND_DISPLAY="$_sock"
else
  for i in $(seq 1 30); do [[ -e "$XDG_RUNTIME_DIR/wayland-0" ]] && break; sleep 1; done
fi
sleep 1

# 2) set the virtual output resolution
OUT="$(wlr-randr 2>/dev/null | awk 'NR==1{print $1}')"
[[ -n "$OUT" ]] && wlr-randr --output "$OUT" --custom-mode "${GEOMETRY}" 2>/dev/null || true
# Where cb-display-resize finds this session (the booth page resizes the output
# to fit the browser through it; see below).
printf '%s\n' "$WAYLAND_DISPLAY" > "$XDG_RUNTIME_DIR/cb-wayland-display"

# 3) wayvnc: wlr-screencopy -> RFB on localhost:$VNC_PORT
wayvnc --render-cursor 0.0.0.0 "$VNC_PORT" >/tmp/cb-wayvnc.log 2>&1 &
WAYVNC_PID=$!
sleep 1

# 4) websockify + noVNC on the booth port
DISPLAY_PORT="${BOOTH_HOST_PORT:-${NOVNC_PORT}}"
echo "🌐 noVNC: http://localhost:${DISPLAY_PORT}/vnc.html?autoconnect=1&resize=remote"
websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}" >/tmp/cb-websockify.log 2>&1 &
WS_PID=$!

cleanup() {
  echo; echo "🛑 stopping ${WAYLAND_COMPOSITOR} session…"
  rm -f "$XDG_RUNTIME_DIR/cb-wayland-display"
  kill "$WS_PID" "$WAYVNC_PID" "$COMPOSITOR_PID" 2>/dev/null || true
  wait "$WS_PID" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

echo "🖥️  ${WAYLAND_COMPOSITOR} (Wayland) via noVNC — connect through the booth port."
wait -n "$COMPOSITOR_PID" "$WAYVNC_PID" "$WS_PID" || true
cleanup
EOF
chmod 0755 "${STARTER_FILE}"

# --- cb-display-resize: fit the desktop to the browser ---
# The booth page opens noVNC with resize=remote, which asks the VNC server to
# resize the desktop to the browser window. TigerVNC (the X11 desktops) does;
# wayvnc 0.7 (Ubuntu 24.04) ignores the request, so the desktop stayed at
# GEOMETRY. It does follow a resize made on the compositor side, live, so the
# booth page reports its size to booth-message-api-server, which runs this hook
# (as the desktop user). Works for labwc and sway alike: both take wlr-randr.
cat > /usr/local/bin/cb-display-resize <<'EOF'
#!/usr/bin/env bash
# cb-display-resize WIDTH HEIGHT — resize the running Wayland desktop's output.
# Installed by wayland--setup.sh; called by booth-message-api-server.
set -u
W="${1:-}"; H="${2:-}"
if [[ ! "$W" =~ ^[0-9]+$ || ! "$H" =~ ^[0-9]+$ ]]; then
  echo "Usage: cb-display-resize WIDTH HEIGHT" >&2
  exit 2
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
if [[ ! -r "$XDG_RUNTIME_DIR/cb-wayland-display" ]]; then
  echo "No Wayland desktop is running for $(id -un)." >&2
  exit 1
fi
WAYLAND_DISPLAY="$(tr -d ' \t\r\n' < "$XDG_RUNTIME_DIR/cb-wayland-display")"
export WAYLAND_DISPLAY
OUT="$(wlr-randr 2>/dev/null | awk 'NR==1{print $1}')"
if [[ -z "$OUT" ]]; then
  echo "No output found on $WAYLAND_DISPLAY." >&2
  exit 1
fi
# Already that size: nothing to do (the page reports on every load).
wlr-randr 2>/dev/null | grep -qE "^ +${W}x${H} px.*current" && exit 0
exec wlr-randr --output "$OUT" --custom-mode "${W}x${H}"
EOF
chmod 0755 /usr/local/bin/cb-display-resize

rm -Rf "${DESKTOP_FILE}"
ln -s  "${STARTER_FILE}" "${DESKTOP_FILE}"

cat <<EOF

✅ labwc (Wayland/noVNC) variant installed.
   Profile: ${PROFILE_FILE}
   Starter: /usr/local/bin/start-wayland
   Font:    FiraCode Nerd Font, default foot font on first run
EOF
