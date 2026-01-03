#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO: $BASH_COMMAND" >&2' ERR

# --- Ensure root ---
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "Must be root"; exit 1; }

# --- Config ---
IDE="$1"              # e.g., pycharm, idea, goland, webstorm
PLUGIN="$2"           # e.g., "Lombook Plugin"

# --- Constant ---
STARTUP_FILE="/usr/share/startup.d/75-ws-${IDE}-plugin--startup.sh"

if ! command -v "${IDE}" >/dev/null 2>&1; then
    echo "$IDE not found."
    exit 1
fi

# --- Create startup script ---
cat > "${STARTUP_FILE}" <<EOF
"${IDE}" installPlugins "${PLUGIN}"
EOF
chmod 755 "${STARTUP_FILE}"

PROFILE_FILE="/etc/profile.d/70-ws-${IDE}--profile.sh"
if [[ -f "${PROFILE_FILE}" ]]; then
    source "${PROFILE_FILE}"
fi
