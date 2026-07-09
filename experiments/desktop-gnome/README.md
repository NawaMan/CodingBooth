# desktop-gnome — parked investigation

Scripts from the (parked) attempt to run **real Ubuntu GNOME Shell on Wayland** in a booth
and stream it to the browser. See the full write-up, verdict, component versions, and restart
plan in **[../../docs/implementations/DESKTOP_GNOME_WAYLAND.md](../../docs/implementations/DESKTOP_GNOME_WAYLAND.md)**.

**Verdict (2026-07-08):** blocked in a normal (non-systemd) container — `gnome-shell`
requires `logind`, which requires systemd as PID 1. Transport-independent (hit by both the
WebRTC and the RDP attempts). The working Wayland desktop that shipped instead is
`desktop-wayland` (labwc + wayvnc).

## Files

- `grd-gonogo.sh` — brings up headless `gnome-shell` + `gnome-remote-desktop` (RDP :3389)
  in a container. Run as the `coder` user. **The fragile part is `systemd-logind`.**
- `rdp-capture.sh` — connects a FreeRDP-3 client into `Xvfb` and screenshots what grd sends,
  to test frame emission headlessly.

## Run (throwaway container)

```bash
# container needs fuse + SYS_ADMIN (grd's clipboard mounts a FUSE fs):
docker run -d --name gtest --device /dev/fuse --cap-add SYS_ADMIN \
  --entrypoint bash nawaman/codingbooth:desktop-gnome-<ver> -c 'sleep infinity'
# (install: gnome-shell gnome-remote-desktop gnome-keyring pipewire wireplumber
#           freerdp3-x11 xvfb imagemagick   — if not already in the image)
docker cp grd-gonogo.sh gtest:/tmp/ ; docker cp rdp-capture.sh gtest:/tmp/
docker exec -d -u coder gtest bash /tmp/grd-gonogo.sh          # bring up gnome + grd
docker exec    -u coder gtest bash /tmp/rdp-capture.sh          # connect + screenshot
docker cp gtest:/tmp/rdp-frame.png .                            # inspect
```

The parked WebRTC pipeline (Attempt 1) lives on git branch `wip/desktop-gnome-webrtc`.
