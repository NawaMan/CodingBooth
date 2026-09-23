# Desktop Terminals Example

Adds Alacritty and Kitty — both GPU-accelerated (OpenGL) terminal emulators — as *alternate*
terminals inside the XFCE desktop variant, alongside its own default (xfce4-terminal).

The interesting part isn't the terminals themselves; it's that they work at all. Alacritty and
Kitty need a working OpenGL context, and a booth's desktop runs headless — no host GPU, driven over
VNC. Both run here through Mesa's `llvmpipe` software rasterizer, which the desktop's `Xvnc` session
already exposes (`glxinfo -B` reports a working GL 4.5 core profile). Nothing extra to configure —
`setup alacritty` / `setup kitty` is the whole ask.

**Stack:** XFCE desktop variant, Alacritty, Kitty

## Quick start

```bash
cd examples/workspaces/desktop-terminals-example
booth      # opens the XFCE desktop in your browser
```

Once the desktop loads, both **Alacritty** and **Kitty** appear as icons directly on the desktop
(alongside Firefox and Chrome) — no need to dig through the application menu. They also appear
there, and the built-in **Terminal Emulator** (xfce4-terminal) is unchanged and still on the panel.
Both start with `FiraCode Nerd Font Mono` at 11pt, seeded once on first container start into
`~/.config/alacritty/alacritty.toml` / `~/.config/kitty/kitty.conf` — edit those files directly
afterwards; the seed never overwrites an existing one.

## What's included

| Component | Details |
|---|---|
| Desktop | XFCE (`--variant xfce`) |
| Alt terminal | Alacritty — GPU-accelerated, Rust |
| Alt terminal | Kitty — GPU-accelerated, C/Python |
| Font | FiraCode Nerd Font Mono, 11pt (seeded once, per terminal) |

See [`docs/MODERN_UX.md`](../../../docs/MODERN_UX.md) for the background — this was suggestion #1
from a review of Omarchy-inspired desktop UX ideas, tried as a standalone experiment.
