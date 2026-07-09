#!/usr/bin/env bash
# desktop-gnome go/no-go — capture what gnome-remote-desktop (RDP) sends, headlessly.
# Run AFTER grd-gonogo.sh has brought up headless gnome-shell + grd (RDP on :3389),
# inside a container started with:  --device /dev/fuse --cap-add SYS_ADMIN
# Renders the RDP session into a virtual framebuffer (Xvfb) and screenshots it.
#
# Expected outcomes:
#   - GNOME desktop in frame.png  -> GREEN: grd emits frames headlessly.
#   - broken pipe / "org.gnome.Mutter.RemoteDesktop was not provided" in the logs
#     -> RED: the logind/session wall (see docs/implementations/DESKTOP_GNOME_WAYLAND.md).
set -x
export DISPLAY=:99
pkill Xvfb 2>/dev/null; pkill xfreerdp3 2>/dev/null; sleep 1
Xvfb :99 -screen 0 1280x800x24 >/tmp/xvfb.log 2>&1 &
sleep 2
setsid xfreerdp3 /v:127.0.0.1:3389 /u:coder /p:codingbooth /cert:ignore \
  /gdi:sw /size:1280x800 /log-level:INFO >/tmp/xrdp.log 2>&1 &
sleep 12
echo "xfreerdp3 alive:"; pgrep -f xfreerdp3 >/dev/null && echo yes || echo no
echo "grd alive:"; pgrep -f gnome-remote-desktop-daemon >/dev/null && echo yes || echo no
import -window root /tmp/rdp-frame.png && echo "captured /tmp/rdp-frame.png ($(wc -c </tmp/rdp-frame.png) bytes)"
echo "=== xfreerdp3 log ==="; grep -iE "error|surface|gfx|rdpgfx|reset|closed" /tmp/xrdp.log | tail -8
echo "=== grd log ==="; tail -5 /tmp/grd.log
