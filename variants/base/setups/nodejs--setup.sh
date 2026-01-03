#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
NODE_MAJOR=20
NVM_VERSION=0.40.3

# --- Parse args ---
# $1 → Node major (if provided)
# optional flag: --nvm-version=<version>
if [[ $# -ge 1 && ! "$1" =~ ^-- ]]; then
  NODE_MAJOR="$1"
  shift
fi

for arg in "$@"; do
  case "$arg" in
    --nvm-version=*)
      NVM_VERSION="${arg#*=}"
      ;;
    *)
      echo "⚠️  Unknown argument: $arg" >&2
      ;;
  esac
done


STARTUP_FILE="/usr/share/startup.d/57-ws-node--startup.sh"
PROFILE_FILE="/etc/profile.d/57-ws-node--profile.sh"

mkdir -p "$(dirname "$STARTUP_FILE")"

# ---- Create startup file: to be executed as normal user on first login ----
cat >"${STARTUP_FILE}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

sudo apt-get remove -y nodejs || true

NODE_MAJOR="${NODE_MAJOR}"
NVM_VERSION="${NVM_VERSION}"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v\${NVM_VERSION}/install.sh"

export NVM_DIR="\${NVM_DIR:-\$HOME/.nvm}"

# If correct Node already installed, skip
if command -v node >/dev/null 2>&1; then
  v="\$(node -v 2>/dev/null || true)"; v="\${v#v}"
  if [ "\${v%%.*}" = "\$NODE_MAJOR" ]; then
    exit 0
  fi
fi

# Install nvm if missing
if [ ! -s "\$NVM_DIR/nvm.sh" ]; then
  mkdir -p "\$NVM_DIR"
  tmp="\${TMPDIR:-/tmp}/nvm.\$\$"
  curl -fsSL -o "\$tmp" "\$NVM_INSTALL_URL"
  bash "\$tmp"
fi

# Load nvm and install Node
# shellcheck disable=SC1090
. "\$NVM_DIR/nvm.sh"
nvm install "\$NODE_MAJOR"
nvm alias default "\$NODE_MAJOR"
nvm use --silent default >/dev/null 2>&1 || true
EOF
chmod 755 "${STARTUP_FILE}"

cat >"$PROFILE_FILE" <<"EOF"
# /etc/profile.d/57-ws-node--profile.sh
# Load nvm (per-user) and quietly select the default Node.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  nvm use --silent default >/dev/null 2>&1 || true
fi
EOF
chmod 644 "$PROFILE_FILE"


echo "✅ Node.js (via nvm) bootstrap ready."
echo "• Requested major: ${NODE_MAJOR}"
echo "• Will install on first user login: ${STARTUP_FILE}"
