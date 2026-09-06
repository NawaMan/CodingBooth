# Turtle Example

This example is a classroom turtle-graphics booth with **two languages drawing the same pictures**. Logo is the Education-catalog editor (`--select logo`, same shape as Scratch / Excalidraw): a JSLogo UI served in the browser. Python turtle is the same geometry in real Python, in a window on the XFCE desktop or in Thonny. Square, star, and tree exist in both, so a student can read one program and write the other. Tcl/Tk is installed for booth Python, Xvfb is there so the Python programs can draw without a display, and the Logo editor is vendored — including CodeMirror — so it does not fetch cdnjs at runtime.

**Stack:** Python 3.13, Thonny, XFCE, Logo (JSLogo), Node.js, Tcl/Tk

## Quick start

```bash
# 1. Launch the booth (XFCE desktop in the browser)
cd examples/workspaces/turtle-example
booth
```

### Python turtle (desktop window)

Inside the booth, or via `booth --`:

```bash
python square.py
python star.py
python tree.py
```

Or open the same files in **Thonny** (**File → Open**, or the folder toolbar) and press Run. The scripts call `hideturtle()` so you see the drawing, not the arrow. File → Open uses Tk dialogs (Zenity is disabled — it does nothing over VNC) and starts in `/home/coder/code`.

### Logo (browser editor)

The catalog **Logo** template runs `setup logo` as root at image build. That installs JSLogo to **`/opt/logo`** and `start-logo` to `/usr/local/bin`. The editor auto-starts from that install on port **18610** (published to the host as 18610). It is **not** served from `/home/coder/code`. Open **http://localhost:18610/**. On desktop variants (XFCE, KDE, LXQt, Wayland) a **Logo** icon is on the desktop, same mechanism as Excalidraw — click it to open the editor.

To load `samples/square.logo` (or star/tree) from the web UI:

1. Click **Open file** (top right) or **Extras → Open a .logo file from this computer**.
2. In the file picker, go to `/home/coder/code/samples` and choose `square.logo`.
3. Click **Run**.

The same three programs are also at the top of the **Examples** sidebar — click one to load it, then Run.

Hide the green turtle in a program:

```logo
hideturtle
fd 100
```

(`ht` is the same command; `showturtle` / `st` brings it back.)

If the server is already up, `start-logo` prints the URL and exits 0 instead of failing with "Address already in use".

## The same three drawings

| Drawing | Logo | Python |
|---------|------|--------|
| Square | `samples/square.logo` | `square.py` |
| Star | `samples/star.logo` | `star.py` |
| Tree | `samples/tree.logo` | `tree.py` |

## What's included

| Component | Details |
|-----------|---------|
| Language | Python 3.13 (booth `python`) |
| Tcl/Tk | `tk` (and its Tcl/Tk libs) so `import turtle` works |
| Teaching IDE | Thonny (desktop variant) |
| Desktop | XFCE |
| Logo editor | Education template `logo` — root install at `/opt/logo`, `start-logo` |
| Headless draw | `xvfb` for tests and `python square.py --output file.ps` |
| Tcl/Tk paths | `turtle_tk.py` points booth Python at the Tcl/Tk 9 bundled in its prefix |

Pin a different Python with the `PYTHON_VERSION` build arg in `.booth/Boothfile`.
