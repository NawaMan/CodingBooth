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

STARTER_FILE=/usr/local/bin/dind-open-port
STOPPER_FILE=/usr/local/bin/dind-close-port

sudo apt-get update
sudo apt-get install -y socat docker.io

cat > "${STARTER_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVER_PORT="$1"
DIND_NAME="${WS_CONTAINER_NAME}-${WS_HOST_PORT}-dind"

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
