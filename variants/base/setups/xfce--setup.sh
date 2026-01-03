#!/usr/bin/env bash
# xfce--setup.sh — root-only installer for XFCE + VNC + noVNC
# Installs deps, creates /usr/local/bin/start-xfce
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- configurable args ----
DEFAULT_DISPLAY="${DEFAULT_DISPLAY:-:1}"
DEFAULT_GEOMETRY="${DEFAULT_GEOMETRY:-1280x800}"
DEFAULT_NOVNC_PORT="${DEFAULT_NOVNC_PORT:-10000}"
DEFAULT_VNC_PORT="${DEFAULT_VNC_PORT:-5901}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-}"

# Use python--setup.sh exactly like setup-code-server-jupyter.sh
PY_VERSION=${1:-3.12}                    # accepts X.Y or X.Y.Z
SETUPS_DIR=${SETUPS_DIR:-/opt/workspace/setups}
"${SETUPS_DIR}/python--setup.sh" "${PY_VERSION}"

# Load python env exported by the base setup
source /etc/profile.d/53-ws-python--profile.sh 2>/dev/null || true

# Profile snippet this script will write to (used later)
PROFILE_FILE="/etc/profile.d/55-ws-desktop-xfce--profile.sh"
STARTER_FILE="/usr/local/bin/start-xfce"
DESKTOP_FILE="/usr/local/bin/start-desktop"


# ---- install base packages ----
export DEBIAN_FRONTEND=noninteractive
apt-get update

apt-get install -y \
  xfce4            \
  xfce4-terminal

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
<meta charset="utf-8">
<title>noVNC</title>
<script>
  const host = location.hostname || 'localhost';
  const port = location.port || '6080';
  const params = new URLSearchParams({
    autoconnect: '1',
    host,
    port,
    path: 'websockify',
    resize: 'remote'
  });
  location.replace('vnc.html?' + params.toString());
</script>
HTML

# ---- profile snippet ----
cat > "${PROFILE_FILE}" <<'EOF'
# XFCE over VNC/noVNC defaults
export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export GEOMETRY=${GEOMETRY:-1280x800}
export NOVNC_PORT=${NOVNC_PORT:-10000}
export VNC_PORT=${VNC_PORT:-5901}
# export VNC_PASSWORD=change-me   # to require password
# export VNC_PASSWORD=            # leave empty (or "none") to disable password

alias desktop-start='start-xfce'

# ---- xfce_setup_info function ----
xfce_setup_info() {
  local DISPLAY_DEF="\${DEFAULT_DISPLAY:-:1}"
  local GEOMETRY_DEF="\${DEFAULT_GEOMETRY:-1280x800}"
  local NOVNC_PORT_DEF="\${DEFAULT_NOVNC_PORT:-10000}"
  local VNC_PORT_DEF="\${DEFAULT_VNC_PORT:-5901}"
  local VNC_PASSWORD_DEF="\${DEFAULT_VNC_PASSWORD:-}"
  local KEYRING_DEF="\${KEYRING_MODE:-basic}"

  local DESKTOP_PACKAGES_DEF="\${DESKTOP_PACKAGES:-xfce4 xfce4-terminal}"
  local VNC_STACK_PACKAGES_DEF="\${VNC_STACK_PACKAGES:-tigervnc-standalone-server novnc websockify dbus-x11}"
  local EXTRA_PACKAGES_DEF="\${EXTRA_PACKAGES:-x11-xserver-utils curl locales software-properties-common}"

  cat <<INFO
───────────────────────────────────────────────────────────────
 XFCE Setup Script — Summary
───────────────────────────────────────────────────────────────

📦 Purpose
    Installs and configures a lightweight XFCE desktop environment
    with VNC and noVNC access inside a container. Creates launcher:
    /usr/local/bin/start-xfce

🚀 What it installs
    - Desktop: \${DESKTOP_PACKAGES_DEF}
    - VNC stack: \${VNC_STACK_PACKAGES_DEF}
    - Extras: \${EXTRA_PACKAGES_DEF}

🧰 Environment defaults
    DISPLAY        = \${DISPLAY_DEF}
    GEOMETRY       = \${GEOMETRY_DEF}
    NOVNC_PORT     = \${NOVNC_PORT_DEF}
    VNC_PORT       = \${VNC_PORT_DEF}
    VNC_PASSWORD   = \${VNC_PASSWORD_DEF}
    KEYRING_MODE   = \${KEYRING_DEF}

🔐 Keyring modes
    basic    — disables GNOME keyring, avoids prompts (default)
    disable  — removes keyring packages entirely
    keep     — keeps keyring active (may show "Default keyring" prompt)

🌐 Access (when start-xfce is running)
    - VNC:      localhost:\${VNC_PORT_DEF}
    - Browser:  http://localhost:\${NOVNC_PORT_DEF}/  (auto-connect)

💡 Usage (as non-root user)
    source \${PROFILE_FILE_DEF}   # usually auto-sourced at login
    start-xfce                   # foreground; Ctrl+C to stop

📁 Generated files
    - \${PROFILE_FILE_DEF}
    - /usr/local/bin/start-xfce
    - ~/.vnc/xstartup (auto-created if missing)
    - ~/.config/autostart/gnome-keyring-*.desktop (per keyring mode)

───────────────────────────────────────────────────────────────
INFO
}
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- start-xfce (foreground only) ----
cat > "${STARTER_FILE}" <<'EOF'
#!/usr/bin/env bash
# start-xfce — foreground-only; Ctrl+C to stop
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

: "${DISPLAY:=:1}"
: "${GEOMETRY:=1280x800}"
: "${NOVNC_PORT:=10000}"
: "${VNC_PASSWORD:=}"
: "${KEYRING_MODE:=basic}"   # basic | disable | keep
: "${HOME:?HOME must be set and writable}"

# infer VNC port from DISPLAY if unset
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

# --- keyring behavior (per-session) -----------------------------------------
case "${KEYRING_MODE}" in
  basic|disable)
    # Stop apps (VS Code/Chrome/etc.) from talking to gnome-keyring/libsecret
    export GNOME_KEYRING_CONTROL=/nonexistent
    unset GNOME_KEYRING_PID SSH_AUTH_SOCK

    # Also hide the per-user autostarts (so daemon won't launch under XFCE)
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
    :
    ;;
  *)
    echo "⚠️ Unknown KEYRING_MODE='${KEYRING_MODE}', defaulting to 'basic'"
    export GNOME_KEYRING_CONTROL=/nonexistent
    unset GNOME_KEYRING_PID SSH_AUTH_SOCK
    ;;
esac
# ---------------------------------------------------------------------------

# pick vnc binary
VNCBIN="$(command -v tigervncserver || command -v vncserver || true)"
if [[ -z "$VNCBIN" ]]; then
  echo "❌ tigervncserver not found" >&2
  exit 3
fi

# auth
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
exec dbus-launch --exit-with-session startxfce4
XEOF
  chmod +x "$XSTART"
fi

# start vnc
if "$VNCBIN" -list 2>/dev/null | grep -qE "^[[:space:]]*${DISPLAY}[[:space:]]"; then
  echo "ℹ️  VNC already running on ${DISPLAY}"
else
  "$VNCBIN" "$DISPLAY" -geometry "$GEOMETRY" -localhost yes "${VNCAUTH_OPTS[@]}"
fi

# start noVNC in foreground
echo "🌐 noVNC: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1&host=localhost&port=${NOVNC_PORT}&path=websockify&resize=scale"
trap 'echo; echo "🛑 stopping…"; "$VNCBIN" -kill "$DISPLAY" || true; exit 0' INT TERM
exec websockify --web=/usr/share/novnc "0.0.0.0:${NOVNC_PORT}" "localhost:${VNC_PORT}"
EOF
chmod 0755 ${STARTER_FILE}

rm -Rf ${DESKTOP_FILE}
ln -s  ${STARTER_FILE} ${DESKTOP_FILE}

# ---- keyring behavior (disable | basic | keep) ----
: "${KEYRING_MODE:=basic}"
echo "🔒 Configuring GNOME keyring mode: ${KEYRING_MODE}"

case "${KEYRING_MODE}" in
  disable)
    echo "  → Disabling keyring packages and autostarts"
    apt-get remove -y gnome-keyring seahorse || true

    mkdir -p /etc/xdg/autostart
    for f in /etc/xdg/autostart/gnome-keyring*.desktop; do
      [[ -f "$f" ]] && sed -i \
        -e 's/^Hidden=.*/Hidden=true/' \
        -e '$aHidden=true' "$f" || true
    done
    ;;

  basic)
    echo "  → Forcing basic password storage (no prompts)"
    cat >> "${PROFILE_FILE}" <<'EOF'
export GNOME_KEYRING_CONTROL=/nonexistent
unset GNOME_KEYRING_PID SSH_AUTH_SOCK
EOF
    ;;

  keep)
    echo "  → Keeping GNOME keyring (you may see the 'Default keyring' prompt)"
    ;;

  *)
    echo "⚠️ Unknown KEYRING_MODE='${KEYRING_MODE}', defaulting to 'basic'"
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
  • Binary:  /usr/local/bin/start-xfce

✅ Defaults:
  DISPLAY=${DEFAULT_DISPLAY}
  GEOMETRY=${DEFAULT_GEOMETRY}
  NOVNC_PORT=${DEFAULT_NOVNC_PORT}
  VNC_PORT=${DEFAULT_VNC_PORT}
  VNC_PASSWORD=${DEFAULT_VNC_PASSWORD}

💡 Usage (as non-root user):
  source ${PROFILE_FILE}   # usually auto-sourced at login
  start-xfce               # runs in foreground; Ctrl+C to stop
EOF
