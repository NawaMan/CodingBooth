#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Installs a startup hook that launches the Kafka broker on container boot.
# Pairs with kafka--setup.sh (which installs and formats storage).
# -----------------------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--topic <NAME>] [--partitions <N>]

Environment overrides:
  KAFKA_TOPIC       (default: devtopic)
  KAFKA_PARTITIONS  (default: 1)

Notes:
- Writes /usr/share/startup.d/65-cb-kafka--startup.sh
- The startup script starts the broker (background) and creates a dev topic.
- Requires kafka--setup.sh to have run first.
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

KAFKA_TOPIC="${KAFKA_TOPIC:-devtopic}"
KAFKA_PARTITIONS="${KAFKA_PARTITIONS:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --topic) shift; KAFKA_TOPIC="${1:-}"; shift ;;
    --partitions) shift; KAFKA_PARTITIONS="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"
KAFKA_DATA="${KAFKA_DATA:-/opt/kafkadata}"
KAFKA_PORT="${KAFKA_PORT:-9092}"

if [[ ! -x "$KAFKA_HOME/bin/kafka-server-start.sh" ]]; then
  echo "❌ Kafka not found at $KAFKA_HOME. Run kafka--setup.sh first."
  exit 1
fi

STARTUP_FILE="/usr/share/startup.d/65-cb-kafka--startup.sh"
mkdir -p "$(dirname "$STARTUP_FILE")"

cat >"$STARTUP_FILE" <<STARTUP
#!/usr/bin/env bash
set -euo pipefail

KAFKA_HOME="${KAFKA_HOME}"
KAFKA_DATA="${KAFKA_DATA}"
KAFKA_CONF="\$KAFKA_DATA/server.properties"
KAFKA_PORT="${KAFKA_PORT}"
KAFKA_TOPIC="${KAFKA_TOPIC}"
KAFKA_PARTITIONS="${KAFKA_PARTITIONS}"

if pgrep -f "kafka.Kafka" >/dev/null 2>&1; then
  exit 0
fi

mkdir -p "\$KAFKA_DATA/logs"
nohup "\$KAFKA_HOME/bin/kafka-server-start.sh" "\$KAFKA_CONF" \\
  > "\$KAFKA_DATA/kafka.log" 2>&1 &

# Wait up to 30s for the broker to accept connections
tries=60
while (( tries-- > 0 )); do
  if nc -z 127.0.0.1 "\$KAFKA_PORT" >/dev/null 2>&1; then break; fi
  sleep 0.5
done

# Create dev topic (idempotent)
if "\$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "127.0.0.1:\$KAFKA_PORT" --list 2>/dev/null \\
    | grep -qx "\$KAFKA_TOPIC"; then
  exit 0
fi
"\$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "127.0.0.1:\$KAFKA_PORT" \\
  --create --topic "\$KAFKA_TOPIC" --partitions "\$KAFKA_PARTITIONS" --replication-factor 1 \\
  >/dev/null 2>&1 || true
STARTUP
chmod 755 "$STARTUP_FILE"

echo "✅ Kafka startup hook installed: $STARTUP_FILE"
echo "   Topic: $KAFKA_TOPIC (partitions=$KAFKA_PARTITIONS)"
