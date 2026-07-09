#!/usr/bin/env bash
# Bring up headless GNOME Shell + gnome-remote-desktop (RDP) in the container.
set -x
export XDG_RUNTIME_DIR=/tmp/xdg-1001; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export LIBGL_ALWAYS_SOFTWARE=1 XDG_SESSION_TYPE=wayland

# root prereqs: Xwayland dir + system dbus + logind
sudo mkdir -p /tmp/.X11-unix && sudo chmod 1777 /tmp/.X11-unix
sudo mkdir -p /run/dbus /run/systemd/system
if ! pgrep -f "dbus-daemon --system" >/dev/null 2>&1; then
  sudo rm -f /run/dbus/system_bus_socket /run/dbus/pid
  sudo dbus-daemon --system --fork; sleep 1
fi
if ! pgrep -x systemd-logind >/dev/null 2>&1; then
  sudo setsid /lib/systemd/systemd-logind >/tmp/logind.log 2>&1 </dev/null & sleep 2
fi

# session bus
eval "$(dbus-launch --sh-syntax)"; export DBUS_SESSION_BUS_ADDRESS
echo "$DBUS_SESSION_BUS_ADDRESS" > /tmp/grd-bus

# gnome-keyring (grd stores RDP creds here) with a seeded default keyring
KR="$HOME/.local/share/keyrings"; rm -rf "$KR"; mkdir -p "$KR"; printf 'login' > "$KR/default"
eval "$(printf 'codingbooth\0' | gnome-keyring-daemon --daemonize --login 2>/dev/null)"
eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null)"
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK

# pipewire (grd captures through it)
pipewire >/tmp/pw.log 2>&1 & sleep 1
wireplumber >/tmp/wp.log 2>&1 & sleep 1

# headless GNOME Shell
gnome-shell --wayland --headless --virtual-monitor 1280x800 >/tmp/gs.log 2>&1 &
for i in $(seq 1 30); do [ -e "$XDG_RUNTIME_DIR/wayland-0" ] && break; sleep 1; done
sleep 3

# grd RDP config
mkdir -p /tmp/grd
openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/grd/k.key -out /tmp/grd/c.crt -days 3650 -subj /CN=cb >/dev/null 2>&1
grdctl rdp set-tls-cert /tmp/grd/c.crt
grdctl rdp set-tls-key  /tmp/grd/k.key
grdctl rdp set-credentials coder codingbooth
grdctl rdp disable-view-only
grdctl rdp enable
grdctl status --show-credentials 2>&1 | grep -iE "username|status|port|password" | head

# grd daemon (screen-share of the running session)
/usr/libexec/gnome-remote-desktop-daemon >/tmp/grd.log 2>&1 &
sleep 5
{ ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null; } | grep 3389 && echo "RDP-UP" || echo "RDP-DOWN"
echo "=== grd log ==="; tail -4 /tmp/grd.log
echo "=== gnome-shell alive ==="; pgrep -u "$(id -u)" -f "gnome-shell --wayland" >/dev/null && echo yes || echo no
sleep infinity
