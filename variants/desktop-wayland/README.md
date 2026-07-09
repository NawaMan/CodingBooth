# desktop-wayland  (experimental)

A **Wayland-native** desktop — [labwc](https://labwc.github.io/) (a
[wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) compositor) — delivered to your
browser. It is the Wayland counterpart to the X11 desktop variants
(`desktop-xfce`, `desktop-kde`, `desktop-lxqt`).

> ⚠️ **Experimental.** This variant is newer and less battle-tested than the X11 desktops.
> It works (labwc + wayvnc + noVNC, validated end-to-end), but expect rough edges and set
> expectations accordingly — for a proven desktop today, use one of the X11 variants.

## How it works

```
labwc (wlroots, headless backend, software render)
  → wayvnc  (wlr-screencopy → RFB)
    → websockify + noVNC  (RFB over the single booth port)
      → browser
```

It reuses the **exact** noVNC delivery as the X11 desktop variants — only the compositor and
VNC server change: TigerVNC (X11) → labwc + wayvnc (Wayland). Because labwc is wlroots-based,
`wlr-screencopy` reliably captures the headless session, and the wlroots headless backend
needs no logind/seat. Existing X11 apps (Firefox, Chrome, VS Code) run via **Xwayland**.

## Usage

```bash
booth run --variant wayland      # alias for desktop-wayland
```

Set the resolution with the `GEOMETRY` env var (default `1280x800`). Launch apps from the
top **waybar** panel (Apps button → `wofi`) or the labwc right-click menu.

## Notes

- **Software rendering** (wlroots pixman) when no GPU is present — fine for typical dev GUI
  use, not GPU/video-heavy workloads.
- **No VNC password by default** (localhost model, like the other desktop variants). Password
  auth for `--public` needs wayvnc TLS setup — a planned follow-up.
- Shell is **labwc** (lightweight), not GNOME/XFCE/KDE.
