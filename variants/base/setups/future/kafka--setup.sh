#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--port <PORT>] [--advertised-host <HOST>] [--data <DIR>] [--topic <NAME>] [--partitions <N>] [--version <VER>]

Environment overrides:
  KAFKA_PORT             (default: 9092)
  KAFKA_ADVERTISED_HOST  (default: 127.0.0.1)
  KAFKA_DATA             (default: /opt/kafkadata)
  KAFKA_TOPIC            (default: devtopic)
  KAFKA_PARTITIONS       (default: 1)
  KAFKA_VERSION          (default: 3.7.0)         # Apache Kafka version
  KAFKA_NODE_ID          (default: 1)
  KAFKA_CTRL_PORT        (default: 9093)
  KAFKA_HOME             (default: /opt/kafka)    # install dir symlink

Examples:
  $0
  KAFKA_ADVERTISED_HOST=host.docker.internal $0 --topic app-events
  $0 --port 19092 --advertised-host myhost --data /data/kafka --topic foo --partitions 3
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults ---
KAFKA_PORT="${KAFKA_PORT:-9092}"
KAFKA_ADVERTISED_HOST="${KAFKA_ADVERTISED_HOST:-127.0.0.1}"
KAFKA_DATA="${KAFKA_DATA:-/opt/kafkadata}"
KAFKA_TOPIC="${KAFKA_TOPIC:-devtopic}"
KAFKA_PARTITIONS="${KAFKA_PARTITIONS:-1}"
KAFKA_VERSION="${KAFKA_VERSION:-3.7.0}"
KAFKA_NODE_ID="${KAFKA_NODE_ID:-1}"
KAFKA_CTRL_PORT="${KAFKA_CTRL_PORT:-9093}"
KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) shift; KAFKA_PORT="${1:-}"; shift ;;
    --advertised-host) shift; KAFKA_ADVERTISED_HOST="${1:-}"; shift ;;
    --data) shift; KAFKA_DATA="${1:-}"; shift ;;
    --topic) shift; KAFKA_TOPIC="${1:-}"; shift ;;
    --partitions) shift; KAFKA_PARTITIONS="${1:-}"; shift ;;
    --version) shift; KAFKA_VERSION="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# --- install deps ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends openjdk-17-jre-headless procps netcat-openbsd
rm -rf /var/lib/apt/lists/*

# --- install kafka (idempotent) ---
SCALA_VER="2.13"
KAFKA_TGZ="kafka_${SCALA_VER}-${KAFKA_VERSION}.tgz"
KAFKA_DIR="/opt/kafka_${SCALA_VER}-${KAFKA_VERSION}"

if [[ ! -d "$KAFKA_DIR" ]]; then
  curl -fsSL "https://downloads.apache.org/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}" -o "/tmp/${KAFKA_TGZ}" \
    || curl -fsSL "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}" -o "/tmp/${KAFKA_TGZ}"
  mkdir -p "$KAFKA_DIR"
  tar -xzf "/tmp/${KAFKA_TGZ}" -C /opt
  mv "/opt/kafka_${SCALA_VER}-${KAFKA_VERSION}" "$KAFKA_DIR" || true
  ln -snf "$KAFKA_DIR" "$KAFKA_HOME"
fi

# --- directories ---
mkdir -p "$KAFKA_DATA" /opt/kafkalogs
touch "$KAFKA_DATA/kafka.log"

# --- config ---
KAFKA_CONF="$KAFKA_DATA/server.properties"
cat >"$KAFKA_CONF" <<EOF
# Single-node KRaft (broker + controller)
process.roles=broker,controller
node.id=${KAFKA_NODE_ID}
controller.listener.names=CONTROLLER
inter.broker.listener.name=PLAINTEXT

# Listeners
listeners=PLAINTEXT://0.0.0.0:${KAFKA_PORT},CONTROLLER://127.0.0.1:${KAFKA_CTRL_PORT}
advertised.listeners=PLAINTEXT://${KAFKA_ADVERTISED_HOST}:${KAFKA_PORT}
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT

# Quorum (single voter)
controller.quorum.voters=${KAFKA_NODE_ID}@127.0.0.1:${KAFKA_CTRL_PORT}

# Storage
log.dirs=${KAFKA_DATA}/logs

# Dev-friendly defaults
num.partitions=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
group.initial.rebalance.delay.ms=0
auto.create.topics.enable=false
EOF

# --- format storage if needed ---
if [[ ! -f "${KAFKA_DATA}/logs/meta.properties" ]]; then
  CLUSTER_ID="$("$KAFKA_HOME/bin/kafka-storage.sh" random-uuid)"
  "$KAFKA_HOME/bin/kafka-storage.sh" format -t "$CLUSTER_ID" -c "$KAFKA_CONF"
fi

# --- helper: wait for port ---
wait_for_port() {
  local host="$1" port="$2" tries=60
  while (( tries-- > 0 )); do
    if nc -z "$host" "$port" >/dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  return 1
}

# --- start server ---
if pgrep -f "kafka.Kafka" >/dev/null 2>&1; then
  echo "ℹ Kafka already running, skipping start"
else
  echo "▶ Starting Kafka..."
  nohup "$KAFKA_HOME/bin/kafka-server-start.sh" "$KAFKA_CONF" \
    > "$KAFKA_DATA/kafka.log" 2>&1 &
fi

wait_for_port 127.0.0.1 "$KAFKA_PORT" || { echo "❌ Kafka did not become ready"; exit 4; }

# --- create dev topic (idempotent) ---
if ! "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "127.0.0.1:${KAFKA_PORT}" --list | grep -qx "$KAFKA_TOPIC"; then
  "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "127.0.0.1:${KAFKA_PORT}" \
    --create --topic "$KAFKA_TOPIC" --partitions "$KAFKA_PARTITIONS" --replication-factor 1
fi

cat <<EOM

✅ Apache Kafka ready for development (single-node KRaft)
  Host:                 0.0.0.0
  Port:                 ${KAFKA_PORT}
  Advertised host:      ${KAFKA_ADVERTISED_HOST}
  Data dir:             ${KAFKA_DATA}
  Controller port:      ${KAFKA_CTRL_PORT} (internal)
  Node ID:              ${KAFKA_NODE_ID}
  Topic:                ${KAFKA_TOPIC} (partitions=${KAFKA_PARTITIONS}, rf=1)
  Kafka version:        ${KAFKA_VERSION}
  Install (symlink):    ${KAFKA_HOME}

Produce/consume test:
  # terminal A
  ${KAFKA_HOME}/bin/kafka-console-producer.sh --bootstrap-server localhost:${KAFKA_PORT} --topic ${KAFKA_TOPIC}
  # terminal B
  ${KAFKA_HOME}/bin/kafka-console-consumer.sh --bootstrap-server localhost:${KAFKA_PORT} --topic ${KAFKA_TOPIC} --from-beginning

List topics:
  ${KAFKA_HOME}/bin/kafka-topics.sh --bootstrap-server localhost:${KAFKA_PORT} --list

Stop server:
  ${KAFKA_HOME}/bin/kafka-server-stop.sh
  # or: pkill -f kafka.Kafka

Logs:
  tail -f ${KAFKA_DATA}/kafka.log

EOM
