# Desktop + noVNC Implementation

This document explains how CodingBooth provides full Linux desktop environments (XFCE, KDE) accessible through a web browser using VNC and noVNC.
Run a full Linux desktop in your browser — no host setup, no X server, no VNC client, no GPU.
CodingBooth’s desktop variants (XFCE, KDE) provide a complete GUI development environment inside a container, streamed securely to your browser using VNC and noVNC. This lets you run heavyweight IDEs, GUI tools, and native Linux applications anywhere, on any machine, with the same reproducible environment your team shares — and when the container stops, everything disappears cleanly.

This document explains how CodingBooth implements browser-accessible desktops, from virtual X servers to WebSocket bridges, startup orchestration, security controls, and UX optimizations.

## Table of Contents

- [Design Goals](#design-goals)
- [Architecture Overview](#architecture-overview)
- [Component Stack](#component-stack)
- [How It Works](#how-it-works)
- [Custom Landing Page](#custom-landing-page)
- [Environment Variables](#environment-variables)
- [Keyring Handling](#keyring-handling)
- [Troubleshooting](#troubleshooting)


## Design Goals

This desktop implementation is designed to:

- Run fully headless (no host display, no GPU, no X server on host)
- Require only a web browser on the host
- Keep all GUI state inside the container
- Avoid persistent system state across restarts
- Minimize security surface (single exposed port, localhost-only VNC)
- Provide frictionless UX (no passwords, no keyring prompts by default)

---

## Architecture Overview

```
Browser (localhost:10000)
    │
    ▼ HTTP/WebSocket
    │
noVNC (JavaScript VNC client)
    │
    ▼ WebSocket on port 10000
    │
websockify (WebSocket-to-TCP proxy)
    │
    ▼ TCP on localhost:5901
    │
TigerVNC Server
    │
    ▼ X11 protocol
    │
XFCE/KDE Desktop Environment
    │
    ▼ Renders to virtual X11 framebuffer (headless, no GPU or physical display)
    │
(Runs entirely in container)
```

---

## Component Stack

| Component | Role | Package |
|-----------|------|---------|
| **TigerVNC** | VNC server with virtual X display | `tigervnc-standalone-server` |
| **noVNC** | Browser-based VNC client | `novnc` |
| **websockify** | WebSocket to TCP proxy | `websockify` |
| **XFCE/KDE** | Desktop environment | `xfce4` / `plasma-desktop` |
| **dbus** | Desktop session bus | `dbus-x11` |

---

## How It Works

### 1. VNC Server Startup

The `start-xfce` or `start-kde` script starts TigerVNC:

```bash
# Pick VNC binary
VNCBIN="$(command -v tigervncserver || command -v vncserver || true)"

# Start VNC server on display :1 (port 5901)
"$VNCBIN" "$DISPLAY" -geometry "$GEOMETRY" -localhost yes "${VNCAUTH_OPTS[@]}"
```

Key flags:
- `$DISPLAY` (`:1`) — Virtual display number
- `-geometry $GEOMETRY` — Resolution (e.g., `1280x800`)
- `-localhost yes` — Only accept local connections (security)
- `-SecurityTypes=None` — Disable VNC password (default)

### 2. X Startup Script

VNC runs `~/.vnc/xstartup` to launch the desktop:

**XFCE:**
```bash
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
xsetroot -solid grey
exec dbus-launch --exit-with-session startxfce4
```

**KDE:**
```bash
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
xsetroot -solid grey
exec dbus-launch --exit-with-session startplasma-x11
```

The `dbus-launch` wrapper is critical — it provides the session bus that desktop applications need.

### 3. WebSocket Proxy

websockify bridges browser WebSockets to VNC's TCP:

```bash
exec websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}"
```

- `--web=/usr/share/novnc` — Serve noVNC static files
- `0.0.0.0:${NOVNC_PORT}` — Listen on all interfaces (port 10000)
- `localhost:${VNC_PORT}` — Connect to VNC server (port 5901)

### 4. noVNC Client

noVNC is a pure JavaScript VNC client. Users access it at:

```
http://localhost:10000/vnc.html?autoconnect=1&host=localhost&port=10000&path=websockify&resize=remote
```

Parameters:
- `autoconnect=1` — Connect immediately
- `resize=remote` — Dynamically resize desktop to match browser window

---

## Custom Landing Page

CodingBooth provides a custom `index.html` that waits for VNC to be ready before redirecting:

```html
<!-- /usr/share/novnc/index.html -->
<script>
  async function vncHtmlExists() {
    const url = `vnc.html?_=${Date.now()}`;  // Cache-bust
    let res = await fetch(url, { method: 'HEAD', cache: 'no-store' });
    return res.ok;
  }

  // Retry every 30 seconds until VNC is ready
  async function checkAndMaybeRedirect() {
    const exists = await vncHtmlExists();
    if (exists) {
      location.replace(redirectUrl);
    } else {
      startCountdownAndRetry();
    }
  }
</script>
```

This prevents "connection refused" errors during container startup.

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DISPLAY` | `:1` | X display number |
| `GEOMETRY` | `1280x800` | Desktop resolution |
| `NOVNC_PORT` | `10000` | Browser access port |
| `VNC_PORT` | `5901` | VNC server port (derived from DISPLAY) |
| `VNC_PASSWORD` | (empty) | VNC password (empty = disabled) |
| `KEYRING_MODE` | `basic` | Keyring handling: `basic`, `disable`, `keep` |

**Display ↔ Port Mapping:**
- VNC port = 5900 + display number
- `DISPLAY=:1` → VNC listens on port 5901
- `DISPLAY=:2` → VNC listens on port 5902

This is useful when debugging multi-display scenarios.

---

## Keyring Handling

Desktop applications (VS Code, Chrome) often want to store secrets in a keyring. This can cause annoying "unlock keyring" popups.

### GNOME Keyring (XFCE)

```bash
case "${KEYRING_MODE}" in
  basic|disable)
    # Stop apps from talking to keyring
    export GNOME_KEYRING_CONTROL=/nonexistent
    unset GNOME_KEYRING_PID SSH_AUTH_SOCK

    # Disable autostart
    for comp in pkcs11 secrets ssh; do
      cat > "${HOME}/.config/autostart/gnome-keyring-${comp}.desktop" <<AUTOSTART
[Desktop Entry]
Hidden=true
X-GNOME-Autostart-enabled=false
AUTOSTART
    done
    ;;
esac
```

### KDE Wallet

```bash
case "${KEYRING_MODE}" in
  basic|disable)
    # Disable KWallet autostart
    for f in org.kde.kwalletd5.desktop kwalletmanager5_autostart.desktop; do
      cat > "${HOME}/.config/autostart/${f}" <<AUTOSTART
[Desktop Entry]
Hidden=true
X-KDE-autostart-condition=false
AUTOSTART
    done
    ;;
esac
```

---

## KDE-Specific Configuration

### Lock Screen Disabled

KDE's lock screen would lock users out (no password is set). The setup script disables it:

```bash
# System-wide defaults
cat > /etc/xdg/kscreenlockerrc <<'CONF'
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
CONF

# Per-session enforcement
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false
pkill -f kscreenlocker || true
```

### Konsole Default Shell

Konsole needs explicit shell configuration to avoid warnings:

```bash
PROFILE_FILE="${HOME}/.local/share/konsole/Shell.profile"
cat > "$PROFILE_FILE" <<'PROF'
[General]
Command=/bin/bash
Name=Shell
Parent=FALLBACK/
PROF
```

### Pinned Applications

Dolphin and Konsole are auto-pinned to the taskbar for convenience:

```bash
APPS=("applications:org.kde.dolphin.desktop" "applications:org.kde.konsole.desktop")
for app in "${APPS[@]}"; do
  append_unique "$CFG" "$sec" "launchers" "$app"
done
```

---

## noVNC Resize Modes

Users can control how the desktop scales in their browser:

| Mode | Behavior | URL Parameter |
|------|----------|---------------|
| `remote` | Desktop resizes to match browser | `resize=remote` (default) |
| `scale` | Desktop scales to fit, keeps resolution | `resize=scale` |
| `off` | 1:1 pixel mapping, may need scrolling | `resize=off` |

Example URL:
```
http://localhost:10000/vnc.html?autoconnect=1&resize=scale
```

---

## Signal Handling

The starter scripts handle graceful shutdown:

```bash
trap 'echo "🛑 stopping…"; "$VNCBIN" -kill "$DISPLAY" || true; exit 0' INT TERM
```

When you press Ctrl+C or the container stops:
1. Trap catches SIGINT/SIGTERM
2. VNC server is killed cleanly
3. Desktop session ends
4. Container exits

---

## Security Considerations

### VNC Authentication Disabled

By default, VNC has no password:
```bash
VNCAUTH_OPTS+=( -SecurityTypes=None )
```

VNC authentication is disabled because:

- The service is bound to localhost only
- Access is typically through port-forwarded or local browser sessions
- Desktop sessions are ephemeral and non-privileged
- Enabling passwords would block automation and break UX

For multi-user or remote scenarios, enable:
- VNC_PASSWORD
- reverse proxy authentication
- TLS termination

This is intentional for ease of use in development. For production:
1. Set `VNC_PASSWORD` environment variable
2. Use a reverse proxy with authentication
3. Keep access limited to localhost/VPN

### Localhost Binding

VNC only listens on localhost:
```bash
"$VNCBIN" "$DISPLAY" -geometry "$GEOMETRY" -localhost yes
```

External access goes through websockify on port 10000, which provides a single controlled entry point.

---

## Troubleshooting

### Useful Logs

```bash
~/.vnc/*.log              # VNC server logs (Xvnc output, errors)
/tmp/.X11-unix/*          # X socket files (verify display exists)
ps aux | grep Xvnc        # Verify X server is running
ps aux | grep websockify  # Verify WebSocket proxy is running
```

### Black Screen

- Desktop environment failed to start
- Check `~/.vnc/*.log` for errors
- Verify dbus is running: `pgrep dbus-daemon`

### "Connection refused"

- VNC server not started yet
- Wait for container startup to complete
- Check if `start-xfce` or `start-kde` is running

### Clipboard Not Working

noVNC doesn't have direct clipboard integration. Use the side panel:
1. Click the arrow on the left edge
2. Select clipboard icon
3. Use the text area to transfer content

### Slow Performance

- Reduce resolution: `GEOMETRY=1024x768`
- Use `resize=scale` instead of `resize=remote`
- Consider using `codeserver` variant if you don't need full desktop

---

## Related Files

- `variants/base/setups/xfce--setup.sh` — XFCE setup script
- `variants/base/setups/kde--setup.sh` — KDE setup script
- `variants/desktop-xfce/Dockerfile` — XFCE variant image
- `variants/desktop-kde/Dockerfile` — KDE variant image
