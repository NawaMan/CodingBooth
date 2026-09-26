# CodingBooth — User Guide

This is the human-facing guide, shipped inside every booth at `/opt/codingbooth/GUIDE.md`. (If
you're an AI agent, read `AGENT.md` in this same directory instead — it's written for you.)

The "CodingBooth Help" button in the floating **Booth** panel (where present) covers the same
ground as this file, in a General tab and a Clipboard tab — plus a tab for anything a setup adds,
such as **i3 Shortcuts (Tiling)** or **Bismuth Shortcuts (Tiling)** when window tiling is installed. Help opens as a floating
window rather than a blocking dialog: the booth stays usable behind it, and you can drag it by its
title and resize it from its bottom-right corner.

---

## General

You're inside a **CodingBooth** — an ephemeral, reproducible dev environment running in a
container. The floating **Booth** panel is your control surface for it:

- **Restart** re-reads your configuration and rebuilds the booth in place.
- **Shut Down** stops and removes the container — anything not saved in your mounted project
  folder is gone after that.
- The **idle indicator**, where shown, tells you idle shutdown is active, and lets you pause or
  disable it if you'll be away from the keyboard but still want the booth running.
- **Full screen**, where shown, puts the booth in full screen and, while it is, takes back
  browser shortcuts (like Ctrl+W) that would otherwise be swallowed by the browser tab instead
  of reaching the booth.

---

## Tiling window manager (i3, desktop booths)

Booths with the `i3` template on XFCE or LXQt can tile windows instead of overlapping them. Run
`start-i3` (or the **Tiling Window Manager (i3)** desktop icon) to switch to i3, and `stop-i3` (or
**Leave Tiling (i3)** in the menu) to switch back — desktop icons are hidden while i3 runs. The
shortcuts are in Help → **i3 Shortcuts (Tiling)**; every one works with **Ctrl+Alt** in any browser, and
with plain Alt in Chrome while **Full screen** is on.

---

## Window tiling on KDE (Bismuth, desktop booths)

Booths with the `bismuth` template on KDE Plasma tile windows with Bismuth, a KWin script — KWin,
the panel and the desktop stay as they are. Run `start-bismuth` (or the **Tiling for KDE (Bismuth)**
desktop icon) to tile, and `stop-bismuth` (or **Leave Tiling (Bismuth)** in the menu) to stop; the
choice is remembered. The shortcuts use **Ctrl+Alt** and are listed in Help → **Bismuth Shortcuts
(Tiling)**; change them in System Settings → Shortcuts → Bismuth, and layouts and gaps in System
Settings → Window Management → Window Tiling.

---

## Clipboard (desktop variants)

XFCE/KDE/LXQt/Wayland desktop booths run over a remote-desktop protocol (VNC) inside your
browser, so your computer's clipboard isn't automatically shared with the desktop the way it
would be on a local machine. There's a dedicated panel for moving text across that boundary:

1. Look for a small gray tab with an arrow, flush against the **left edge** of the desktop. Click
   it to slide out the control bar. (Our overlay panel points an arrow at it the first time you
   open a desktop booth, in case it's easy to miss.)
2. In that bar, click the **clipboard icon**.
3. A **Clipboard** panel opens with a text box.
   - **To get text into the desktop:** paste (or type) it into that box. It's sent to the remote
     session, so you can then paste it normally (Ctrl+V) inside any app running in the booth.
   - **To get text back out:** this direction is less reliable today — the desktop images don't
     yet bridge the in-desktop clipboard to this panel automatically, so copying something inside
     an app may not always show up here. If it doesn't, select and copy again from inside the app,
     or use the panel's send direction in reverse where the app supports pasting from it directly.
   - **Clear** empties the box.

This is a real limitation of the current setup, not just this panel — it's tracked in
`docs/TODO.md` under "Desktop variants' clipboard still needs noVNC's manual side panel" if you
want the technical detail.
