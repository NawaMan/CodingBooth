#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===================== Must be root =====================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root


STARTER_FILE=/usr/local/bin/dind-open-port
STOPPER_FILE=/usr/local/bin/dind-close-port

sudo apt-get update
sudo apt-get install -y socat docker.io

cat > "${STARTER_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVER_PORT="$1"
DIND_NAME="${BOOTH_CONTAINER_NAME}-${BOOTH_HOST_PORT}-dind"

# fully detach socat from this shell
setsid socat "TCP-LISTEN:${SERVER_PORT},reuseaddr,fork" \
             "TCP:${DIND_NAME}:${SERVER_PORT}" \
             </dev/null >/dev/null 2>&1 &

SOCAT_PID=$!
printf '%s\n' "$SOCAT_PID"
EOF
sudo chmod 755 "${STARTER_FILE}"


cat > "${STOPPER_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SOCAT_PID="$1"

if [[ "$SOCAT_PID" == "" ]]; then
    "Parameter 1 (SOCAT_PID)  is not given."
    exit 1
fi

echo "Stopping socat..."
if [ -n "${SOCAT_PID:-}" ] && kill -0 "$SOCAT_PID" 2>/dev/null; then
kill "$SOCAT_PID" 2>/dev/null || true
wait "$SOCAT_PID" 2>/dev/null || true
fi
EOF
sudo chmod 755 "${STOPPER_FILE}"


# ---- startup script: drop host-only credential helpers from docker config ----
# Numbered before the autostart segments (floci, appwrite, ...) that pull images.
STARTUP_FILE="/usr/share/startup.d/40-cb-dind--startup.sh"
mkdir -p "$(dirname "${STARTUP_FILE}")"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -uo pipefail

# dind startup script
# Docker Desktop hosts write "credsStore": "desktop" (and credHelpers entries)
# into ~/.docker/config.json. The docker-config extension seeds that file into
# the booth, where those helper binaries do not exist, so every `docker pull`
# fails with "docker-credential-desktop: executable file not found". Drop the
# helper references that cannot be resolved here; plain "auths" entries stay.

CONFIG="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
[[ -f "$CONFIG" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

helpers=$(jq -r '[.credsStore // empty] + [(.credHelpers // {})[]] | unique[]' "$CONFIG" 2>/dev/null) || exit 0

missing=()
while IFS= read -r helper; do
    [[ -z "$helper" ]] && continue
    command -v "docker-credential-$helper" >/dev/null 2>&1 || missing+=("$helper")
done <<< "$helpers"
[[ ${#missing[@]} -eq 0 ]] && exit 0

missing_json=$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)
tmp="$CONFIG.cb-tmp.$$"
if jq --argjson missing "$missing_json" '
      (if (.credsStore // null) as $s | $s != null and ($missing | index($s))
         then del(.credsStore) else . end)
    | (if .credHelpers
         then .credHelpers |= with_entries(select(.value as $v | ($missing | index($v)) | not))
            | (if .credHelpers == {} then del(.credHelpers) else . end)
         else . end)
    ' "$CONFIG" > "$tmp" 2>/dev/null && mv -f "$tmp" "$CONFIG" 2>/dev/null; then
    echo "Removed unavailable docker credential helper(s) from $CONFIG: ${missing[*]}"
else
    rm -f "$tmp"
fi
exit 0
STARTUP
chmod 755 "${STARTUP_FILE}"
