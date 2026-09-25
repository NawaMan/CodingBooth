# Desktop XFCE Variant

Lightweight desktop environment with full GUI support.

**Includes:**
- XFCE desktop environment: Greybird-dark apps and window borders, Reversal-dark icons, Gruppled
  White cursor — more themes via the `tela-icons`, `orchis-gtk` and `material-cursors` templates
- `booth--theme` to show or switch the look from any shell (`booth--theme set icons Adwaita`)
- [Plank Reloaded](https://github.com/zquestz/plank-reloaded) dock (Matte theme, always visible)
  in place of XFCE's bottom panel — Ctrl+right-click the dock for its Preferences
- [Cortile](https://github.com/leukipp/cortile) auto-tiling, installed but off — `cortile &`
  to try it, or `xfce+cortile` to start it on login
- Firefox, Google Chrome, Chromium browsers
- Python 3.12
- VS Code desktop, without GitHub Copilot (~290 MB lighter; select the `vscode-copilot` template
  to keep it)
- Jupyter extensions
- GTK theme support

**Usage:**
```bash
booth --variant desktop-xfce
```

**Access:** Connect via VNC or noVNC web interface for full desktop experience.

**Purpose:** Lightweight, fast desktop environment for GUI applications and web development.
