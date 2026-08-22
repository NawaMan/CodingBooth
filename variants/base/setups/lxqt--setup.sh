#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# lxqt--setup.sh — root-only installer for LXQt + VNC + noVNC
# Installs deps, configures defaults, creates /usr/local/bin/start-lxqt
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root


# ---- configurable args ----
DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-:1}"
DEFAULT_GEOMETRY="${DEFAULT_GEOMETRY:-1280x800}"
DEFAULT_NOVNC_PORT="${DEFAULT_NOVNC_PORT:-10000}"
DEFAULT_VNC_PORT="${DEFAULT_VNC_PORT:-5901}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-}"
LXQT_WM="${LXQT_WM:-openbox}"    # can be xfwm4 if installed

# Use python--setup.sh exactly like setup-code-server-jupyter.sh
PY_VERSION=${1:-3.12}                    # accepts X.Y or X.Y.Z
SETUPS_DIR=${SETUPS_DIR:-/opt/codingbooth/setups}
"${SETUPS_DIR}/python--setup.sh" "${PY_VERSION}"

# Load python env exported by the base setup
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

# Profile snippet this script will write to
PROFILE_FILE="/etc/profile.d/55-cb-desktop-lxqt--profile.sh"
STARTER_FILE="/usr/local/bin/start-lxqt"
DESKTOP_FILE="/usr/local/bin/start-desktop"

# ---- install base packages ----
export DEBIAN_FRONTEND=noninteractive
apt-get update

apt-get install -y \
  lxqt-core        \
  lxqt-session     \
  openbox          \
  qterminal

apt-get install  -y          \
  tigervnc-standalone-server \
  novnc                      \
  websockify                 \
  dbus-x11

apt-get install -y  \
  x11-xserver-utils \
  curl              \
  locales           \
  software-properties-common

apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- sanity check for noVNC ----
if [[ ! -d /usr/share/novnc ]]; then
  echo "❌ /usr/share/novnc not found" >&2
  exit 2
fi

# ---- Make autoconnect entrypoint for noVNC ----
cat >/usr/share/novnc/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>noVNC</title>

  <!-- Best effort client-side cache prevention (server headers are better) -->
  <meta http-equiv="Cache-Control" content="no-store, no-cache, must-revalidate, max-age=0" />
  <meta http-equiv="Pragma" content="no-cache" />
  <meta http-equiv="Expires" content="0" />

  <style>
    body {
      font-family: system-ui, sans-serif;
      margin: 0;                 /* remove margin so centering is exact */
      line-height: 1.4;
      min-height: 100vh;

      /* CENTER CONTENT */
      display: flex;
      align-items: center;      /* vertical center */
      justify-content: center;  /* horizontal center */
    }

    .card {
      max-width: 680px;
      padding: 1.25rem 1.5rem;
      border: 1px solid #ddd;
      border-radius: 12px;
    }

    .muted { color: #666; }

    button {
      padding: 0.6rem 0.9rem;
      border-radius: 10px;
      border: 1px solid #ccc;
      cursor: pointer;
    }

    button:disabled {
      opacity: 0.6;
      cursor: not-allowed;
    }

    .row {
      display: flex;
      gap: 0.75rem;
      align-items: center;
      flex-wrap: wrap;
      margin-top: 1rem;
    }

    .status { margin-top: 0.75rem; }

    code {
      background: #f6f6f6;
      padding: 0.15rem 0.35rem;
      border-radius: 6px;
    }
  </style>
</head>

<body>
  <div class="card">
    <h1>Connecting to VNC…</h1>
    <p class="muted" id="subtitle">Checking if <code>vnc.html</code> is ready.</p>

    <div class="status" id="status"></div>

    <div class="row">
      <button id="recheckBtn" type="button">Recheck now</button>
      <span class="muted" id="countdown"></span>
    </div>
  </div>

  <script>
    // ---- Config ----
    const CHECK_URL = 'vnc.html';
    const RETRY_SECONDS = 30;

    // noVNC redirect params (your existing logic)
    const host = location.hostname || 'localhost';
    const port = location.port || '6080';
    const params = new URLSearchParams({
      autoconnect: '1',
      host,
      port,
      path: 'websockify',
      resize: 'remote'
    });
    const redirectUrl = CHECK_URL + '?' + params.toString();

    // ---- UI helpers ----
    const statusEl = document.getElementById('status');
    const subtitleEl = document.getElementById('subtitle');
    const countdownEl = document.getElementById('countdown');
    const recheckBtn = document.getElementById('recheckBtn');

    function setStatus(html) {
      statusEl.innerHTML = html;
    }

    // ---- Cache-busting & existence check ----
    async function vncHtmlExists() {
      // Add a cache-buster query param so any intermediary cache is bypassed
      const url = `${CHECK_URL}?_=${Date.now()}`;

      try {
        // Try HEAD first (lightweight). Some servers don’t allow HEAD; fall back to GET.
        let res = await fetch(url, { method: 'HEAD', cache: 'no-store' });
        if (res.ok) return true;

        // If HEAD not allowed or failed, try GET.
        res = await fetch(url, { method: 'GET', cache: 'no-store' });
        return res.ok;
      } catch {
        return false;
      }
    }

    // ---- Retry loop with countdown ----
    let timer = null;
    let remaining = RETRY_SECONDS;

    function stopTimer() {
      if (timer) clearInterval(timer);
      timer = null;
    }

    function startCountdownAndRetry() {
      stopTimer();
      remaining = RETRY_SECONDS;

      countdownEl.textContent = `Retrying in ${remaining}s…`;
      recheckBtn.disabled = false;

      timer = setInterval(async () => {
        remaining -= 1;
        if (remaining > 0) {
          countdownEl.textContent = `Retrying in ${remaining}s…`;
          return;
        }

        stopTimer();
        countdownEl.textContent = `Rechecking now…`;
        await checkAndMaybeRedirect();
      }, 1000);
    }

    async function checkAndMaybeRedirect() {
      recheckBtn.disabled = true;
      subtitleEl.textContent = `Checking if ${CHECK_URL} is ready…`;
      setStatus(`<span class="muted">Please wait.</span>`);

      const exists = await vncHtmlExists();

      if (exists) {
        subtitleEl.textContent = `VNC is ready. Redirecting…`;
        setStatus(`<span>Opening <code>${CHECK_URL}</code>…</span>`);
        // Replace so user won't go "back" to the waiting screen
        location.replace(redirectUrl);
        return;
      }

      // Not ready
      subtitleEl.textContent = `VNC is not ready yet.`;
      setStatus(`
        <strong>VNC is not ready.</strong>
        <div class="muted">We’ll automatically recheck in ${RETRY_SECONDS} seconds, or you can recheck now.</div>
      `);
      recheckBtn.disabled = false;
      startCountdownAndRetry();
    }

    // Button: immediate recheck
    recheckBtn.addEventListener('click', async () => {
      stopTimer();
      countdownEl.textContent = '';
      await checkAndMaybeRedirect();
    });

    // Initial check
    checkAndMaybeRedirect();
  </script>
</body>
</html>
HTML

# ---- Preseed LXQt window manager (system-wide) ----
mkdir -p /etc/xdg/lxqt
cat > /etc/xdg/lxqt/session.conf <<EOF
[General]
window_manager=${LXQT_WM}
EOF

# ---- profile snippet ----
cat > "${PROFILE_FILE}" <<'EOF'
# LXQt over VNC/noVNC defaults
export DISPLAY=${DEFAULT_DISPLAY}
export GEOMETRY=${GEOMETRY:-${DEFAULT_GEOMETRY}}
export NOVNC_PORT=${NOVNC_PORT:-${DEFAULT_NOVNC_PORT}}
export VNC_PORT=${VNC_PORT:-${DEFAULT_VNC_PORT}}
# export VNC_PASSWORD=change-me   # to require password
# export VNC_PASSWORD=            # leave empty (or "none") to disable password

alias desktop-start='start-lxqt'

lxqt_setup_info() {
  local DISPLAY_DEF="\${DEFAULT_DISPLAY:-:1}"
  local GEOMETRY_DEF="\${DEFAULT_GEOMETRY:-1280x800}"
  local NOVNC_PORT_DEF="\${DEFAULT_NOVNC_PORT:-10000}"
  local VNC_PORT_DEF="\${DEFAULT_VNC_PORT:-5901}"
  local VNC_PASSWORD_DEF="\${DEFAULT_VNC_PASSWORD:-}"
  local KEYRING_DEF="\${KEYRING_MODE:-basic}"
  local PROFILE_FILE_DEF="${PROFILE_FILE}"

  cat <<INFO
───────────────────────────────────────────────────────────────
 LXQt Setup Script — Summary
───────────────────────────────────────────────────────────────

📦 Purpose
    Installs and configures a lightweight LXQt desktop environment
    with VNC and noVNC access inside a container. Creates launcher:
    /usr/local/bin/start-lxqt

🧰 Environment defaults
    DISPLAY        = \${DISPLAY_DEF}
    GEOMETRY       = \${GEOMETRY_DEF}
    NOVNC_PORT     = \${NOVNC_PORT_DEF}
    VNC_PORT       = \${VNC_PORT_DEF}
    VNC_PASSWORD   = \${VNC_PASSWORD_DEF}
    KEYRING_MODE   = \${KEYRING_DEF}

🌐 Access (when start-lxqt is running)
    - VNC:      localhost:\${VNC_PORT_DEF}
    - Browser:  http://localhost:\${NOVNC_PORT_DEF}/  (auto-connect)

💡 Usage (as non-root user)
    source \${PROFILE_FILE_DEF}
    start-lxqt                    # foreground; Ctrl+C to stop
───────────────────────────────────────────────────────────────
INFO
}
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- desktop launcher trust (pcmanfm-qt / libfm-qt) ----
# pcmanfm-qt flags every ~/Desktop launcher with an "untrusted" emblem and asks
# to confirm before running, until the launcher is marked trusted. libfm-qt
# stores that trust as the GIO metadata attribute metadata::trusted, which must
# be set *before* the desktop renders (setting it afterwards does not refresh the
# emblem). start-lxqt's xstartup runs this from inside the session D-Bus, just
# before startlxqt launches the pcmanfm-qt desktop.
cat > /usr/local/bin/cb-lxqt-trust-icons <<'EOF'
#!/bin/bash
command -v gio >/dev/null 2>&1 || exit 0
shopt -s nullglob
for f in "$HOME"/Desktop/*.desktop; do
  gio set "$f" metadata::trusted true 2>/dev/null || true
done
exit 0
EOF
chmod 0755 /usr/local/bin/cb-lxqt-trust-icons

# ---- start-lxqt ----
cat > /usr/local/bin/start-lxqt <<'EOF'
#!/usr/bin/env bash
# start-lxqt — foreground-only; Ctrl+C to stop
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

: "${DISPLAY:=:1}"
: "${GEOMETRY:=1280x800}"
: "${NOVNC_PORT:=10000}"
: "${VNC_PASSWORD:=}"
: "${KEYRING_MODE:=basic}"
: "${LXQT_WM:=openbox}"
: "${HOME:?HOME must be set and writable}"

# infer VNC port
if [[ -z "${VNC_PORT:-}" ]]; then
  if [[ "$DISPLAY" =~ ^:([0-9]+)$ ]]; then
    VNC_PORT="$((5900 + ${BASH_REMATCH[1]}))"
  else
    VNC_PORT=5901
  fi
fi

# runtime dir
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

# keyring behavior
case "${KEYRING_MODE}" in
  basic|disable)
    export GNOME_KEYRING_CONTROL=/nonexistent
    unset GNOME_KEYRING_PID SSH_AUTH_SOCK
    mkdir -p "${HOME}/.config/autostart"
    for comp in pkcs11 secrets ssh; do
      cat > "${HOME}/.config/autostart/gnome-keyring-${comp}.desktop" <<AUTOSTART
[Desktop Entry]
Type=Application
Name=GNOME Keyring: ${comp}
Exec=/usr/bin/gnome-keyring-daemon --start --components=${comp}
Hidden=true
X-GNOME-Autostart-enabled=false
AUTOSTART
    done
    ;;
  keep)
    ;;
  *)
    export GNOME_KEYRING_CONTROL=/nonexistent
    unset GNOME_KEYRING_PID SSH_AUTH_SOCK
    ;;
esac

# Pre-seed LXQt config so no WM dialog appears
mkdir -p "${HOME}/.config/lxqt"
SESSION_CONF="${HOME}/.config/lxqt/session.conf"
if ! grep -q '^window_manager=' "$SESSION_CONF" 2>/dev/null; then
  echo "[General]" > "$SESSION_CONF"
  echo "window_manager=${LXQT_WM}" >> "$SESSION_CONF"
fi

# VNC auth
VNCBIN="$(command -v tigervncserver || command -v vncserver || true)"
if [[ -z "$VNCBIN" ]]; then
  echo "❌ tigervncserver not found" >&2
  exit 3
fi

mkdir -p "${HOME}/.vnc"
VNCAUTH_OPTS=()
if [[ -n "${VNC_PASSWORD}" && "${VNC_PASSWORD,,}" != "none" ]]; then
  if [[ ! -s "${HOME}/.vnc/passwd" ]]; then
    echo "${VNC_PASSWORD}" | vncpasswd -f > "${HOME}/.vnc/passwd"
    chmod 600 "${HOME}/.vnc/passwd"
  fi
else
  VNCAUTH_OPTS+=( -SecurityTypes=None )
  rm -f "${HOME}/.vnc/passwd" 2>/dev/null || true
fi

# xstartup
XSTART="${HOME}/.vnc/xstartup"
if [[ ! -x "$XSTART" ]]; then
  cat > "$XSTART" <<'XEOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
xsetroot -solid grey
# Mark ~/Desktop launchers trusted (inside the session bus) before the desktop
# renders, so pcmanfm-qt shows no "untrusted launcher" emblem / prompt.
exec dbus-launch --exit-with-session sh -c 'cb-lxqt-trust-icons; exec startlxqt'
XEOF
  chmod +x "$XSTART"
fi

# start VNC
if "$VNCBIN" -list 2>/dev/null | grep -qE "^[[:space:]]*${DISPLAY}[[:space:]]"; then
  echo "ℹ️  VNC already running on ${DISPLAY}"
else
  "$VNCBIN" "$DISPLAY" -geometry "$GEOMETRY" -localhost yes "${VNCAUTH_OPTS[@]}"
fi

# start noVNC in background, monitor VNC server for desktop logout
DISPLAY_PORT="${BOOTH_HOST_PORT:-${NOVNC_PORT}}"
echo "🌐 noVNC: http://localhost:${DISPLAY_PORT}/vnc.html?autoconnect=1&host=localhost&port=${DISPLAY_PORT}&path=websockify&resize=scale"
websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}" &
WS_PID=$!

cleanup() {
  echo
  echo "🛑 stopping…"
  kill $WS_PID 2>/dev/null || true
  "$VNCBIN" -kill "$DISPLAY" || true
  wait $WS_PID 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

# Wait for VNC server to exit (e.g. desktop logout/shutdown)
VNC_PIDFILE="${HOME}/.vnc/$(hostname)${DISPLAY}.pid"
while true; do
  VNC_PID=$(cat "$VNC_PIDFILE" 2>/dev/null) || break
  kill -0 "$VNC_PID" 2>/dev/null         || break
  sleep 2
done

echo
echo "🖥️  Desktop session ended."
kill $WS_PID 2>/dev/null || true
wait $WS_PID 2>/dev/null || true
exit 0
EOF
chmod 0755 ${STARTER_FILE}

rm -Rf ${DESKTOP_FILE}
ln -s  ${STARTER_FILE} ${DESKTOP_FILE}

# ---- keyring behavior ----
: "${KEYRING_MODE:=basic}"
echo "🔒 Configuring GNOME keyring mode: ${KEYRING_MODE}"

case "${KEYRING_MODE}" in
  disable)
    apt-get remove -y gnome-keyring seahorse || true
    mkdir -p /etc/xdg/autostart
    for f in /etc/xdg/autostart/gnome-keyring*.desktop; do
      [[ -f "$f" ]] && sed -i -e 's/^Hidden=.*/Hidden=true/' -e '$aHidden=true' "$f" || true
    done
    ;;
  basic)
    cat >> "${PROFILE_FILE}" <<'EOF'
export GNOME_KEYRING_CONTROL=/nonexistent
unset GNOME_KEYRING_PID SSH_AUTH_SOCK
EOF
    ;;
  keep)
    ;;
  *)
    cat >> "${PROFILE_FILE}" <<'EOF'
export GNOME_KEYRING_CONTROL=/nonexistent
unset GNOME_KEYRING_PID SSH_AUTH_SOCK
EOF
    ;;
esac

# ---- summary ----
cat <<EOF

✅ Files:
  • Profile: ${PROFILE_FILE}
  • Binary:  /usr/local/bin/start-lxqt

✅ Defaults:
  DISPLAY=${DEFAULT_DISPLAY}
  GEOMETRY=${DEFAULT_GEOMETRY}
  NOVNC_PORT=${DEFAULT_NOVNC_PORT}
  VNC_PORT=${DEFAULT_VNC_PORT}
  VNC_PASSWORD=${DEFAULT_VNC_PASSWORD}
  LXQT_WM=${LXQT_WM}

💡 Usage (as non-root user):
  source ${PROFILE_FILE}
  start-lxqt
EOF
