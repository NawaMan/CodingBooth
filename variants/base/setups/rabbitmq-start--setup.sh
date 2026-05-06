#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Installs a startup hook that launches RabbitMQ on container boot and ensures
# a dev user + vhost exist. Pairs with rabbitmq--setup.sh.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--user <USER>] [--pass <PASS>] [--vhost <VHOST>]

Environment overrides:
  RABBIT_USER   (default: devuser)
  RABBIT_PASS   (default: devpass)
  RABBIT_VHOST  (default: /dev)

Notes:
- Writes /usr/share/startup.d/65-cb-rabbitmq--startup.sh
- The startup script starts the broker (detached) and provisions user/vhost.
- Requires rabbitmq--setup.sh to have run first.
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

RABBIT_USER="${RABBIT_USER:-devuser}"
RABBIT_PASS="${RABBIT_PASS:-devpass}"
RABBIT_VHOST="${RABBIT_VHOST:-/dev}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)  shift; RABBIT_USER="${1:-}"; shift ;;
    --pass)  shift; RABBIT_PASS="${1:-}"; shift ;;
    --vhost) shift; RABBIT_VHOST="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

if ! command -v rabbitmq-server >/dev/null 2>&1; then
  echo "❌ rabbitmq-server not found. Run rabbitmq--setup.sh first."
  exit 1
fi

STARTUP_FILE="/usr/share/startup.d/65-cb-rabbitmq--startup.sh"
mkdir -p "$(dirname "$STARTUP_FILE")"

cat >"$STARTUP_FILE" <<STARTUP
#!/usr/bin/env bash
set -euo pipefail

RABBIT_USER="${RABBIT_USER}"
RABBIT_PASS="${RABBIT_PASS}"
RABBIT_VHOST="${RABBIT_VHOST}"

# Start broker if not already running
if ! rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
  rabbitmq-server -detached
fi

# Wait up to 30s for ping to succeed
tries=60
until rabbitmq-diagnostics -q ping >/dev/null 2>&1; do
  ((tries--)) || { echo "rabbitmq did not become ready" >&2; exit 0; }
  sleep 0.5
done

# vhost (idempotent)
if ! rabbitmqctl list_vhosts -q | grep -Fx -- "\$RABBIT_VHOST" >/dev/null; then
  rabbitmqctl add_vhost "\$RABBIT_VHOST"
fi

# user (idempotent)
if ! rabbitmqctl list_users -q | awk '{print \$1}' | grep -Fx -- "\$RABBIT_USER" >/dev/null; then
  rabbitmqctl add_user "\$RABBIT_USER" "\$RABBIT_PASS"
fi
rabbitmqctl set_user_tags "\$RABBIT_USER" administrator
rabbitmqctl set_permissions -p "\$RABBIT_VHOST" "\$RABBIT_USER" ".*" ".*" ".*"

# Drop default 'guest' if still present
if rabbitmqctl list_users -q | awk '{print \$1}' | grep -Fx -- guest >/dev/null; then
  rabbitmqctl delete_user guest >/dev/null 2>&1 || true
fi
STARTUP
chmod 755 "$STARTUP_FILE"

echo "✅ RabbitMQ startup hook installed: $STARTUP_FILE"
echo "   User: $RABBIT_USER  VHost: $RABBIT_VHOST"
