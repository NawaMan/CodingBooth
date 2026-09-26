# i3 Desktop Example

The XFCE desktop with the **i3 tiling window manager** in place of XFCE's own (xfwm4): windows split
the screen instead of overlapping, and you drive them from the keyboard. The rest of XFCE stays —
the top panel, menu, tray, Thunar, notifications, and the Plank dock.

**Stack:** XFCE desktop variant + the `i3` template (`--select i3`) with its default extensions

## Quick start

```bash
cd examples/workspaces/i3-desktop-example
booth      # opens the desktop in your browser, already tiling
```

Open a couple of apps from the dock and watch them tile side by side. The booth panel's
**CodingBooth Help → i3 Shortcuts (Tiling)** tab lists every key; the ones you need first:

| Keys | Does |
|---|---|
| `Ctrl+Alt+Enter` | Open a terminal |
| `Ctrl+Alt+h / j / k / l` | Move focus left / down / up / right |
| `Ctrl+Alt+Shift+h / j / k / l` | Move the window |
| `Ctrl+Alt+1 … 0` | Switch workspace |
| `Ctrl+Alt+f` | Full screen the window |
| `Ctrl+Alt+Shift+q` | Close the window |
| `Ctrl+Alt+Shift+e` | Leave tiling (back to xfwm4) |

Every shortcut also works with plain **Alt** when the browser lets go of it — in Chrome, turn on the
panel's **Full screen** button, which captures the whole keyboard. Firefox keeps Alt for itself, so
use Ctrl+Alt there.

## Switching back and forth

Tiling is a window-manager switch inside the same desktop session, not a different desktop:

```bash
stop-i3     # back to xfwm4, with desktop icons (also: Ctrl+Alt+Shift+e, or "Leave Tiling (i3)" in the menu)
start-i3    # tile again (also: the "Tiling Window Manager (i3)" desktop icon)
```

Desktop icons are hidden while i3 runs — i3 has no desktop layer — and come back with `stop-i3`.

## What's included

| Piece | From |
|---|---|
| i3, `start-i3` / `stop-i3`, desktop icon, Help tab | `i3` template (`setup i3`) |
| i3 at login | `i3+default` (auto) — drop with `i3~default` to log in on xfwm4 |
| Ctrl+Alt twin of every shortcut | `i3+ctrl-alt` (auto) |
| 8px window gaps | `i3+gaps` (auto) — `i3+gaps:12` for more |

The same `i3` selection works on the LXQt desktop (`--variant lxqt`), and does nothing on a booth
with no XFCE or LXQt. To change bindings, copy `/etc/xdg/i3/config` to `~/.config/i3/config`.
