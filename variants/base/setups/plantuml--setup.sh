#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION] [PORT]

Arguments:
  VERSION  PlantUML version (default: 1.2025.2)
  PORT     Port for the PlantUML web server (default: 18080)

Examples:
  $0                     # install with defaults
  $0 1.2025.2 18080      # specific version and port

Notes:
- Installs Java (if not present), PlantUML jar, and PlantUML Server
- CLI available as 'plantuml' command
- Web UI available at http://localhost:<PORT>
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- defaults / args ----
PLANTUML_VERSION="${1:-1.2025.2}"
PLANTUML_PORT="${2:-18080}"
PLANTUML_DIR="/opt/plantuml"
PLANTUML_JAR="${PLANTUML_DIR}/plantuml.jar"
PLANTUML_SERVER_WAR="${PLANTUML_DIR}/plantuml-server.war"

STARTER_FILE="/usr/local/bin/start-plantuml"
CLI_FILE="/usr/local/bin/plantuml"

# ---- install Java if not present ----
if command -v java >/dev/null 2>&1; then
  echo "• Java already installed: $(java -version 2>&1 | head -1)"
else
  echo "• Installing Java (default-jre) ..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends default-jre-headless
  rm -rf /var/lib/apt/lists/*
fi

# ---- install graphviz (required by PlantUML for many diagram types) ----
if command -v dot >/dev/null 2>&1; then
  echo "• Graphviz already installed"
else
  echo "• Installing Graphviz ..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends graphviz
  rm -rf /var/lib/apt/lists/*
fi

# ---- download PlantUML jar ----
mkdir -p "$PLANTUML_DIR"

echo "• Downloading PlantUML ${PLANTUML_VERSION} ..."
curl -fsSL -o "$PLANTUML_JAR" \
  "https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"

# ---- download PlantUML Server war ----
echo "• Downloading PlantUML Server ${PLANTUML_VERSION} ..."
curl -fsSL -o "$PLANTUML_SERVER_WAR" \
  "https://github.com/plantuml/plantuml-server/releases/download/v${PLANTUML_VERSION}/plantuml-v${PLANTUML_VERSION}.war"

# ---- install Jetty for serving the war ----
if ! command -v java >/dev/null 2>&1; then
  echo "❌ Java is required but not found"
  exit 1
fi

JETTY_VERSION="12.0.16"
JETTY_DIR="/opt/plantuml/jetty"
if [[ ! -d "$JETTY_DIR" ]]; then
  echo "• Downloading Jetty Runner ..."
  mkdir -p "$JETTY_DIR"
  curl -fsSL -o "${JETTY_DIR}/jetty-runner.jar" \
    "https://repo1.maven.org/maven2/org/eclipse/jetty/jetty-runner/${JETTY_VERSION}/jetty-runner-${JETTY_VERSION}.jar" \
    || {
      # Fallback: use jetty-home
      echo "• Jetty runner not available, using standalone runner ..."
      curl -fsSL -o "${JETTY_DIR}/jetty-runner.jar" \
        "https://repo1.maven.org/maven2/org/eclipse/jetty/ee10/jetty-ee10-runner/${JETTY_VERSION}/jetty-ee10-runner-${JETTY_VERSION}.jar"
    }
fi

# ---- create CLI wrapper ----
cat > "${CLI_FILE}" <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
exec java -jar /opt/plantuml/plantuml.jar "$@"
CLI
chmod 755 "${CLI_FILE}"

# ---- create web server starter ----
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-__PLANTUML_PORT__}

echo "Starting PlantUML Server on http://localhost:$PORT ..."
exec java -jar /opt/plantuml/jetty/jetty-runner.jar \
  --port "$PORT" \
  /opt/plantuml/plantuml-server.war
STARTER
sed -i "s/__PLANTUML_PORT__/${PLANTUML_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
# Register a desktop icon that opens the PlantUML server in a browser
# (desktop variants only).
cb-web-icon.sh --id plantuml --name "PlantUML" --icon applications-internet \
  --port "${PLANTUML_PORT}" --path / --start start-plantuml

echo "✅ PlantUML installed."
echo "   Version:    ${PLANTUML_VERSION}"
echo "   CLI:        ${CLI_FILE}"
echo "   Server WAR: ${PLANTUML_SERVER_WAR}"
echo "   Port:       ${PLANTUML_PORT}"
echo "   Starter:    ${STARTER_FILE}"
echo ""
echo "ℹ️  CLI usage:      plantuml diagram.puml"
echo "   Web UI launch:  start-plantuml [PORT]"
echo "   Access:         http://localhost:${PLANTUML_PORT}"
