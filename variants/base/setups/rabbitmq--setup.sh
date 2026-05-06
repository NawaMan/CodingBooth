#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--port <PORT>] [--mgmt-port <PORT>] [--data <DIR>] [--node <NAME>]

Environment overrides:
  RABBIT_VERSION  (default: latest)             # match against apt-cache madison rabbitmq-server
  RABBIT_PORT     (default: 5672)
  RABBIT_DATA     (default: /opt/rabbitmq)
  RABBIT_MGMTPORT (default: 15672)
  RABBIT_NODENAME (default: rabbit@localhost)

Notes:
- Installs the rabbitmq-server package and writes config; broker is NOT started.
- User/vhost provisioning happens at container boot via the 'start' extension.
- To auto-start the broker on container boot, also enable the 'start' extension
  (e.g., 'install rabbitmq+start' or call rabbitmq-start--setup.sh directly).
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults ---
RABBIT_VERSION="${RABBIT_VERSION:-latest}"
RABBIT_PORT="${RABBIT_PORT:-5672}"
RABBIT_DATA="${RABBIT_DATA:-/opt/rabbitmq}"
RABBIT_MGMTPORT="${RABBIT_MGMTPORT:-15672}"
RABBIT_NODENAME="${RABBIT_NODENAME:-rabbit@localhost}"

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)    shift; RABBIT_VERSION="${1:-latest}"; shift ;;
    --port)       shift; RABBIT_PORT="${1:-}"; shift ;;
    --data)       shift; RABBIT_DATA="${1:-}"; shift ;;
    --mgmt-port)  shift; RABBIT_MGMTPORT="${1:-}"; shift ;;
    --node)       shift; RABBIT_NODENAME="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# --- install (idempotent) ---
if ! command -v rabbitmq-server >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates gnupg apt-utils
  if [[ "$RABBIT_VERSION" == "latest" || -z "$RABBIT_VERSION" ]]; then
    apt-get install -y --no-install-recommends rabbitmq-server
  else
    CANDIDATE="$(apt-cache madison rabbitmq-server 2>/dev/null | awk -v v="$RABBIT_VERSION" '$3 ~ v {print $3; exit}')"
    if [[ -z "$CANDIDATE" ]]; then
      echo "❌ RabbitMQ version '$RABBIT_VERSION' not available in apt. Try 'latest' or one of:"
      apt-cache madison rabbitmq-server | awk '{print "   - " $3}' | head -5
      exit 1
    fi
    echo "📦 Installing rabbitmq-server=$CANDIDATE"
    apt-get install -y --no-install-recommends "rabbitmq-server=$CANDIDATE"
  fi
  rm -rf /var/lib/apt/lists/*
fi

# Some distro packages auto-enable the systemd unit; inside Docker we don't
# want it running during build. Best-effort stop (ignore errors when no init).
if pgrep -f "beam.*rabbit" >/dev/null 2>&1; then
  rabbitmqctl stop >/dev/null 2>&1 || true
fi

# --- prepare dirs ---
mkdir -p "$RABBIT_DATA"/{mnesia,log}
chown -R root:root "$RABBIT_DATA"

# --- config: env + server settings ---
mkdir -p /etc/rabbitmq

cat >/etc/rabbitmq/rabbitmq-env.conf <<EOF
RABBITMQ_NODENAME=$RABBIT_NODENAME
RABBITMQ_MNESIA_BASE=$RABBIT_DATA/mnesia
RABBITMQ_LOG_BASE=$RABBIT_DATA/log
EOF

cat >/etc/rabbitmq/rabbitmq.conf <<EOF
# Bind AMQP to all interfaces for dev
listeners.tcp = 0.0.0.0:${RABBIT_PORT}

# Management UI on all interfaces
management.tcp.ip   = 0.0.0.0
management.tcp.port = ${RABBIT_MGMTPORT}

# Dev-friendly: allow connections from anywhere (the start extension creates a real user)
loopback_users.guest = false

# Keep disk headroom small for containers
disk_free_limit.absolute = 50MB
EOF

# Enable management plugin offline (no daemon needed)
rabbitmq-plugins enable --offline rabbitmq_management >/dev/null

cat <<EOM

✅ RabbitMQ installed and configured (NOT running)
  Install:        $(dpkg -s rabbitmq-server 2>/dev/null | awk '/^Version:/{print $2}')
  Data dir:       $RABBIT_DATA
  AMQP port:      $RABBIT_PORT
  Mgmt UI port:   $RABBIT_MGMTPORT
  Node name:      $RABBIT_NODENAME

The broker is NOT running. To start it:
  - manually: rabbitmq-server -detached  (then create user/vhost via rabbitmqctl)
  - on container boot: enable the 'rabbitmq+start' extension in your Boothfile

EOM
