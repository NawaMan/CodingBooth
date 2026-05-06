#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <VER>] [--port <PORT>] [--advertised-host <HOST>] [--data <DIR>]

Environment overrides:
  KAFKA_VERSION          (default: 3.7.0)         # Apache Kafka version
  KAFKA_PORT             (default: 9092)
  KAFKA_ADVERTISED_HOST  (default: 127.0.0.1)
  KAFKA_DATA             (default: /opt/kafkadata)
  KAFKA_NODE_ID          (default: 1)
  KAFKA_CTRL_PORT        (default: 9093)
  KAFKA_HOME             (default: /opt/kafka)    # install dir symlink

Examples:
  $0
  KAFKA_ADVERTISED_HOST=host.docker.internal $0
  $0 --port 19092 --advertised-host myhost --data /data/kafka

Notes:
- Installs Apache Kafka (KRaft mode) and formats storage; broker is NOT started.
- To auto-start the broker on container boot, also enable the 'start' extension
  (e.g., 'install kafka+start' or call kafka-start--setup.sh directly).
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults ---
KAFKA_VERSION="${KAFKA_VERSION:-3.7.0}"
KAFKA_PORT="${KAFKA_PORT:-9092}"
KAFKA_ADVERTISED_HOST="${KAFKA_ADVERTISED_HOST:-127.0.0.1}"
KAFKA_DATA="${KAFKA_DATA:-/opt/kafkadata}"
KAFKA_NODE_ID="${KAFKA_NODE_ID:-1}"
KAFKA_CTRL_PORT="${KAFKA_CTRL_PORT:-9093}"
KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; KAFKA_VERSION="${1:-}"; shift ;;
    --port) shift; KAFKA_PORT="${1:-}"; shift ;;
    --advertised-host) shift; KAFKA_ADVERTISED_HOST="${1:-}"; shift ;;
    --data) shift; KAFKA_DATA="${1:-}"; shift ;;
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

# --- profile: expose kafka bin on PATH ---
cat >/etc/profile.d/65-cb-kafka--profile.sh <<EOF
# Apache Kafka
export KAFKA_HOME=${KAFKA_HOME}
export PATH="\$KAFKA_HOME/bin:\$PATH"
EOF
chmod 0644 /etc/profile.d/65-cb-kafka--profile.sh

cat <<EOM

✅ Apache Kafka ${KAFKA_VERSION} installed (single-node KRaft)
  Install:        ${KAFKA_HOME}
  Config:         ${KAFKA_CONF}
  Data dir:       ${KAFKA_DATA}
  Default port:   ${KAFKA_PORT}

The broker is NOT running. To start it:
  - manually: ${KAFKA_HOME}/bin/kafka-server-start.sh ${KAFKA_CONF}
  - on container boot: enable the 'kafka+start' extension in your Boothfile

EOM
