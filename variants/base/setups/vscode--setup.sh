#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# vscode--setup.sh — Install Visual Studio Code (DEB, no snap)
# Adds: Jupyter Notebook + Bash kernel setup (for VS Code Jupyter extension)
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

# ---- root check ----
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# Work around hash-sum-mismatch issues under emulation (libgcrypt)
mkdir -p /etc/gcrypt
echo all > /etc/gcrypt/hwf.deny

# ---------------- Load environment from profile.d ----------------
# These set: PY_STABLE, PY_STABLE_VERSION, PY_SERIES, VENV_SERIES_DIR, PATH tweaks, etc.
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

PROFILE_FILE="/etc/profile.d/70-cb-vscode-jupyter--profile.sh"

export DEBIAN_FRONTEND=noninteractive

echo "🔧 Installing Visual Studio Code (no snap)…"

# add Microsoft’s key
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
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

# ---- Jupyter + Bash kernel setup ----
echo "🔧 Installing Jupyter + Bash kernel…"

pip install --upgrade pip setuptools wheel
pip install jupyter ipykernel bash_kernel

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

# Default X server settings.
export DISPLAY=:1
export XAUTHORITY="$HOME/.Xauthority"

VSCODE_EXTENSION_DIR="${VSCODE_EXTENSION_DIR:-/usr/local/share/code/extensions}"

DATA_DIR="${HOME}/.vscode-data"
mkdir -p "${DATA_DIR}"

exec /usr/bin/code                           \
  --no-sandbox                               \
  --disable-gpu                              \
  --password-store=basic                     \
  --user-data-dir="${DATA_DIR}"              \
  --extensions-dir="${VSCODE_EXTENSION_DIR}" \
  --disable-workspace-trust                  \
  "$HOME/code"                               \
  "$@"
EOF
chmod 755 "$STARTER_FILE"

# Froce the desktop launcher to use the executor we create.
if [[ -f /usr/share/applications/code.desktop ]]; then
  sed -i 's#^Exec=.*#Exec=/usr/local/bin/code %F#' /usr/share/applications/code.desktop || true
fi

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
