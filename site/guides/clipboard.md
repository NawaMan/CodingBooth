# Using the clipboard in a CodingBooth desktop

If you opened this from the **Full screen** panel or the hint pointing at the tab on the left
edge of a desktop booth (XFCE, KDE, LXQt, Wayland), here's what that tab is for.

## Why it's needed

A desktop booth runs over a remote-desktop protocol (VNC) inside your browser. Your computer's
clipboard isn't automatically shared with it the way it would be with a program running locally —
the browser and the desktop are two separate clipboards until you bridge them.

## The clipboard panel

1. Find the small gray tab with an arrow, flush against the **left edge** of the desktop, and
   click it to slide out the control bar.
2. Click the **clipboard icon** in that bar.
3. A **Clipboard** panel opens with a text box.
   - **Local → booth:** paste or type text into the box. It's sent to the remote session, so you
     can then paste it normally (Ctrl+V) inside any app running in the booth.
   - **Booth → local:** less reliable today — copying something inside an app in the booth doesn't
     always show up in this box automatically, since the desktop images don't yet bridge the
     in-desktop clipboard to it. If it doesn't appear, copy again from inside the app, or select
     and copy the text manually.
   - **Clear** empties the box.

This asymmetry is a known limitation, not a bug in your setup — improving it is tracked as an open
item in the project.

---

[← Back to codingbooth.io](/)
