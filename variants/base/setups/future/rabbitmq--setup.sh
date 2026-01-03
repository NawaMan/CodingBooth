#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--port <PORT>] [--user <USER>] [--pass <PASS>] [--vhost <VHOST>] [--data <DIR>] [--mgmt-port <PORT>] [--node <NAME>]

Environment overrides:
  RABBIT_PORT     (default: 5672)
  RABBIT_USER     (default: devuser)
  RABBIT_PASS     (default: devpass)
  RABBIT_VHOST    (default: /dev)
  RABBIT_DATA     (default: /opt/rabbitmq)
  RABBIT_MGMTPORT (default: 15672)
  RABBIT_NODENAME (default: rabbit@localhost)   # good for single-node/dev

Examples:
  $0
  RABBIT_PORT=5673 $0 --user foo --pass bar --vhost /app --data /data/rabbit --mgmt-port 18072
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults ---
RABBIT_PORT="${RABBIT_PORT:-5672}"
RABBIT_USER="${RABBIT_USER:-devuser}"
RABBIT_PASS="${RABBIT_PASS:-devpass}"
RABBIT_VHOST="${RABBIT_VHOST:-/dev}"
RABBIT_DATA="${RABBIT_DATA:-/opt/rabbitmq}"
RABBIT_MGMTPORT="${RABBIT_MGMTPORT:-15672}"
RABBIT_NODENAME="${RABBIT_NODENAME:-rabbit@localhost}"

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)       shift; RABBIT_PORT="${1:-}"; shift ;;
    --user)       shift; RABBIT_USER="${1:-}"; shift ;;
    --pass)       shift; RABBIT_PASS="${1:-}"; shift ;;
    --vhost)      shift; RABBIT_VHOST="${1:-}"; shift ;;
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
  apt-get install -y --no-install-recommends rabbitmq-server curl ca-certificates gnupg
  rm -rf /var/lib/apt/lists/*
fi

# --- prepare dirs ---
mkdir -p "$RABBIT_DATA"/{mnesia,log}
chown -R root:root "$RABBIT_DATA"

# --- config: env + server settings ---
mkdir -p /etc/rabbitmq

# environment (directories & node name)
cat >/etc/rabbitmq/rabbitmq-env.conf <<EOF
RABBITMQ_NODENAME=$RABBIT_NODENAME
RABBITMQ_MNESIA_BASE=$RABBIT_DATA/mnesia
RABBITMQ_LOG_BASE=$RABBIT_DATA/log
EOF

# server config (listeners & management UI)
cat >/etc/rabbitmq/rabbitmq.conf <<EOF
# Bind AMQP to all interfaces for dev
listeners.tcp = 0.0.0.0:${RABBIT_PORT}

# Management UI on all interfaces
management.tcp.ip   = 0.0.0.0
management.tcp.port = ${RABBIT_MGMTPORT}

# Dev-friendly: allow connections from anywhere (we create our own user)
loopback_users.guest = false

# Keep disk headroom small for containers
disk_free_limit.absolute = 50MB
EOF

# ensure management plugin is on (works even if server is down with --offline)
rabbitmq-plugins enable --offline rabbitmq_management >/dev/null

# --- start server (detached) ---
if rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
  echo "ℹ RabbitMQ already running, proceeding..."
else
  echo "▶ Starting RabbitMQ..."
  rabbitmq-server -detached
fi

# --- wait until ready ---
tries=60
until rabbitmq-diagnostics -q ping >/dev/null 2>&1; do
  ((tries--)) || { echo "❌ RabbitMQ did not become ready"; exit 3; }
  sleep 0.5
done

# --- create vhost (idempotent) ---
if ! rabbitmqctl list_vhosts -q | grep -Fx -- "$RABBIT_VHOST" >/dev/null; then
  rabbitmqctl add_vhost "$RABBIT_VHOST"
fi

# --- create admin user (idempotent), grant full perms on vhost ---
if ! rabbitmqctl list_users -q | awk '{print $1}' | grep -Fx -- "$RABBIT_USER" >/dev/null; then
  rabbitmqctl add_user "$RABBIT_USER" "$RABBIT_PASS"
fi
rabbitmqctl set_user_tags "$RABBIT_USER" administrator
rabbitmqctl set_permissions -p "$RABBIT_VHOST" "$RABBIT_USER" ".*" ".*" ".*"

# (optional) remove default guest user if present
if rabbitmqctl list_users -q | awk '{print $1}' | grep -Fx -- guest >/dev/null; then
  rabbitmqctl delete_user guest || true
fi

cat <<EOM

✅ RabbitMQ ready for development
  Host:          0.0.0.0
  AMQP port:     $RABBIT_PORT
  Mgmt UI port:  $RABBIT_MGMTPORT
  User:          $RABBIT_USER  (administrator)
  Password:      $RABBIT_PASS
  VHost:         $RABBIT_VHOST
  Node name:     $RABBIT_NODENAME
  Data dir:      $RABBIT_DATA

Connect (AMQP 0-9-1):
  amqp://$RABBIT_USER:$RABBIT_PASS@localhost:$RABBIT_PORT$RABBIT_VHOST

Open Management UI:
  http://localhost:$RABBIT_MGMTPORT  (login: $RABBIT_USER / $RABBIT_PASS)

Smoke test (send/receive with rabbitmqadmin):
  # download the CLI (if not present)
  curl -fsSL "http://localhost:$RABBIT_MGMTPORT/cli/rabbitmqadmin" -o /usr/local/bin/rabbitmqadmin && chmod +x /usr/local/bin/rabbitmqadmin
  rabbitmqadmin --host localhost --port $RABBIT_MGMTPORT --username "$RABBIT_USER" --password "$RABBIT_PASS" \
    declare queue name=devqueue durable=false
  rabbitmqadmin --host localhost --port $RABBIT_MGMTPORT --username "$RABBIT_USER" --password "$RABBIT_PASS" \
    publish routing_key=devqueue payload="hello"
  rabbitmqadmin --host localhost --port $RABBIT_MGMTPORT --username "$RABBIT_USER" --password "$RABBIT_PASS" \
    get queue=devqueue requeue=false

Stop server:
  rabbitmqctl stop

Logs:
  tail -f "$RABBIT_DATA/log/"*.log
EOM
