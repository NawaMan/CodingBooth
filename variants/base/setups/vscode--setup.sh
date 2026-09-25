#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# vscode--setup.sh — Install Visual Studio Code (DEB, no snap)
# Adds: Jupyter Notebook + Bash kernel setup (for VS Code Jupyter extension)
#
# GitHub Copilot is stripped by default: the `code` package bundles it as a
# built-in extension plus a native runtime (~290 MB of a ~970 MB install). Pass
# --keep-copilot to leave it in, or add it back to a stripped image with
# vscode-copilot--setup.sh (the vscode-copilot template).
#
# Usage: vscode--setup.sh [--keep-copilot]
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

KEEP_COPILOT=false
if [[ "${1:-}" == "--keep-copilot" ]]; then
  KEEP_COPILOT=true
fi
# Marker read by the /usr/local/bin/code wrapper (to seed chat.disableAIFeatures)
# and by vscode-copilot--setup.sh (to know there is something to restore).
COPILOT_STRIPPED_MARKER=/etc/codingbooth/vscode-copilot-stripped


# Work around hash-sum-mismatch issues under emulation (libgcrypt)
mkdir -p /etc/gcrypt
echo all > /etc/gcrypt/hwf.deny

# ---------------- Load environment from profile.d ----------------
# These set: PY_STABLE, PY_STABLE_VERSION, PY_SERIES, VENV_SERIES_DIR, PATH tweaks, etc.
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

PROFILE_FILE="/etc/profile.d/70-cb-vscode-jupyter--profile.sh"

export DEBIAN_FRONTEND=noninteractive

echo "🔧 Installing Visual Studio Code (no snap)…"

# add Microsoft’s key
install -d -m 0755 /etc/apt/keyrings
# Staged to a file rather than piped: a retried transfer restarts from the
# beginning, so a consumer already reading the stream would see the truncated
# first attempt followed by the whole body. Downloading first removes that hazard
# and lets --retry-all-errors cover a registry 5xx.
MS_KEY="$(mktemp)"
curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "$MS_KEY" https://packages.microsoft.com/keys/microsoft.asc
gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg < "$MS_KEY"
rm -f "$MS_KEY"
chmod 0644 /etc/apt/keyrings/packages.microsoft.gpg

# clean old repo entries
for f in /etc/apt/sources.list          \
         /etc/apt/sources.list.d/*.list \
         /etc/apt/sources.list.d/*.sources; do
  [[ -f "$f" ]] && sed -i '/packages\.microsoft\.com\/repos\/code/d' "$f" || true
done
rm -f /etc/apt/sources.list.d/vscode.list /etc/apt/sources.list.d/vscode.sources || true

# add repo
arch="$(dpkg --print-architecture)"
cat > /etc/apt/sources.list.d/vscode.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main
EOF
chmod 0644 /etc/apt/sources.list.d/vscode.list

# install VS Code
apt-get clean
rm -rf /var/lib/apt/lists/*
apt-get update || echo "⚠️ apt-get update failed; continuing with existing indexes" >&2
apt-get install -y code
echo "✅ VS Code installed"

# ---- Strip GitHub Copilot (unless --keep-copilot) ----
# Only the two Copilot folders go; VS Code runs normally without them. Its core
# still tries to start the Copilot client and logs "Unable to resolve
# @github/copilot SDK runtime paths" on every launch, so the wrapper below also
# seeds "chat.disableAIFeatures": true, which stops that entirely.
VSCODE_APP=/usr/share/code/resources/app
if [[ "$KEEP_COPILOT" == "true" ]]; then
  rm -f "$COPILOT_STRIPPED_MARKER"
else
  rm -rf "$VSCODE_APP/extensions/copilot" \
         "$VSCODE_APP"/node_modules.asar.unpacked/@github/copilot-sdk-*
  install -d /etc/codingbooth
  dpkg-query -W -f='${Version}\n' code > "$COPILOT_STRIPPED_MARKER"
  echo "✅ GitHub Copilot stripped from VS Code (restore: setup vscode-copilot)"
fi

# ---- Jupyter + Bash kernel setup ----
echo "🔧 Installing Jupyter + Bash kernel…"

pip install --upgrade pip setuptools wheel
pip install jupyter "ipykernel>=6" bash_kernel

# Register both kernels system-wide
python -m ipykernel install   --sys-prefix --name=python3 --display-name="Python 3 (${CB_PY_VERSION})"
python -m bash_kernel.install --sys-prefix

# Make Jupyter path globally visible for VS Code
cat > "$PROFILE_FILE" <<'EOF'
# Added by vscode--setup.sh
export JUPYTER_PATH="${VENV_ROOT}/share/jupyter:/usr/local/share/jupyter:/usr/share/jupyter:\${JUPYTER_PATH:-}"
EOF
chmod 644 "$PROFILE_FILE"

echo "✅ Jupyter + Bash kernel ready for VS Code"

# TODO: centralize this some how
VSCODE_EXTENSION_DIR="${VSCODE_EXTENSION_DIR:-/usr/local/share/code/extensions}"
mkdir -p   "${VSCODE_EXTENSION_DIR}"
chmod 0777 "${VSCODE_EXTENSION_DIR}"

STARTER_FILE=/usr/local/bin/code
cat > "$STARTER_FILE" <<'EOF'
#!/usr/bin/env bash

# Default X server settings. Respect the session's DISPLAY when set — VNC-based
# desktops (XFCE/KDE/LXQt) export :1, while the Wayland variant runs Xwayland on
# :0. Falling back to :1 keeps the old behavior when DISPLAY is unset.
export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="$HOME/.Xauthority"

VSCODE_EXTENSION_DIR="${VSCODE_EXTENSION_DIR:-/usr/local/share/code/extensions}"

DATA_DIR="${HOME}/.vscode-data"
mkdir -p "${DATA_DIR}"

# Integrated terminal font — seeded once, like the desktop-terminal configs
# (xfce4-terminal/Konsole/qterminal/foot). Only writing it when the file is
# still absent means a later font change made from VS Code's own Settings is
# never overwritten. Gated on the font actually being installed, though every
# variant that ships this launcher already runs its desktop setup (which
# installs it) first.
#
# AI features are turned off the same way, once, when this image had Copilot
# stripped (see vscode--setup.sh) — otherwise VS Code keeps trying to start it.
SETTINGS_JSON="${DATA_DIR}/User/settings.json"
if [[ ! -f "$SETTINGS_JSON" ]]; then
  SEED=()
  if [[ -f /usr/share/fonts/truetype/fira-code-nerd-font/FiraCodeNerdFontMono-Regular.ttf ]]; then
    SEED+=('"terminal.integrated.fontFamily": "FiraCode Nerd Font Mono"'
           '"editor.fontFamily": "FiraCode Nerd Font Mono"')
  fi
  if [[ -f /etc/codingbooth/vscode-copilot-stripped ]]; then
    SEED+=('"chat.disableAIFeatures": true')
  fi
  if [[ ${#SEED[@]} -gt 0 ]]; then
    mkdir -p "$(dirname "$SETTINGS_JSON")"
    { echo "{"
      for i in "${!SEED[@]}"; do
        sep=","; [[ $i -eq $(( ${#SEED[@]} - 1 )) ]] && sep=""
        echo "  ${SEED[$i]}${sep}"
      done
      echo "}"
    } > "$SETTINGS_JSON"
  fi
fi

# --disable-dev-shm-usage: the container's /dev/shm defaults to 64 MB, too small
# for Chromium's renderer shared memory. Rendering a rich notebook overflows it and
# the renderer aborts ("renderer process gone, code 133"). Point Chromium at /tmp.
exec /usr/bin/code                           \
  --no-sandbox                               \
  --disable-gpu                              \
  --disable-dev-shm-usage                    \
  --password-store=basic                     \
  --user-data-dir="${DATA_DIR}"              \
  --extensions-dir="${VSCODE_EXTENSION_DIR}" \
  --disable-workspace-trust                  \
  "$HOME/code"                               \
  "$@"
EOF
chmod 755 "$STARTER_FILE"

# Force the desktop launchers to use the executor we create. Newer `code`
# packages ship com.microsoft.VSCode*.desktop instead of code*.desktop; a
# launcher left on /usr/share/code/code runs Electron without --no-sandbox and
# it aborts ("Failed to move to new namespace", exit 133). Only the binary is
# swapped, so each Exec keeps its own args (--new-window, --open-url %U, …).
VSCODE_LAUNCHERS=()
for f in /usr/share/applications/code.desktop                     \
         /usr/share/applications/code-url-handler.desktop         \
         /usr/share/applications/com.microsoft.VSCode.desktop    \
         /usr/share/applications/com.microsoft.VSCode.UrlHandler.desktop; do
  [[ -f "$f" ]] || continue
  sed -i -E 's#^Exec=(/usr/share/code/code|/usr/bin/code)( |$)#Exec=/usr/local/bin/code\2#' "$f"
  if grep -qE '^Exec=(/usr/share/code/code|/usr/bin/code)( |$)' "$f"; then
    echo "❌ Unrewritten Exec line left in $f" >&2
    exit 1
  fi
  VSCODE_LAUNCHERS+=("$f")
done

# Register a VS Code desktop icon (no-ops on non-desktop variants) — the main
# launcher under whichever name the package uses, never the URL handler.
for f in "${VSCODE_LAUNCHERS[@]}"; do
  case "$f" in
    */code.desktop|*/com.microsoft.VSCode.desktop) cb-desktop-icon.sh "$f"; break ;;
  esac
done

echo "✅ VS Code configured to use --no-sandbox by default"
echo "✅ Environment prepared for Jupyter notebooks + Bash kernel"

cat <<EOF

🎉 Setup complete!

You can now open VS Code and install:
  • ms-toolsai.jupyter
  • ms-python.python

Your Jupyter kernels available:
  - Python 3 (venv)
  - Bash

To verify inside VS Code:
  1. Open a .ipynb notebook
  2. Select 'Python 3 (venv)' or 'Bash' kernel
EOF
