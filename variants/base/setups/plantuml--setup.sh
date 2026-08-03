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

# Jetty **11**, and a real distribution rather than jetty-runner. Both details are
# load-bearing, and the previous combination (jetty-runner 12.0.16) served
# `503 Service Unavailable` forever — the war never deployed, so the server bound
# its port in ~1s and then answered nothing. Measured, not guessed:
#
#   jetty-runner 12.0.16 (as shipped)  → 503 forever
#   jetty-ee10 / ee9 / ee8 runner 12   → 503 forever
#   jetty-home 12 + ee9 modules        → 503 forever
#   jetty-runner 11.0.24               → deploys, renders SVG, but the JSP editor
#                                        dies with "No InstanceManager set"
#   jetty-home 11.0.24 + jsp module    → HTTP 200 in ~2s, Monaco editor, renders ✅
#
# The war is `web-app 5.0` (Jakarta EE 9), which is Jetty 11 natively; Jetty 12's
# "ee9" is a compatibility layer and is not the same thing. The `jsp` module is
# what supplies the Jasper InstanceManager the editor JSPs need — jetty-runner
# has no way to set one up, which is why the distribution is used instead.
JETTY_VERSION="11.0.24"
JETTY_HOME="/opt/plantuml/jetty-home"
JETTY_BASE="/opt/plantuml/jetty-base"
if [[ ! -d "$JETTY_HOME" ]]; then
  echo "• Downloading Jetty ${JETTY_VERSION} ..."
  mkdir -p "$JETTY_HOME"
  TMP_JETTY="$(mktemp)"
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "$TMP_JETTY" \
    "https://repo1.maven.org/maven2/org/eclipse/jetty/jetty-home/${JETTY_VERSION}/jetty-home-${JETTY_VERSION}.tar.gz"
  tar xzf "$TMP_JETTY" -C "$JETTY_HOME" --strip-components=1
  rm -f "$TMP_JETTY"
fi

echo "• Configuring Jetty base ..."
mkdir -p "$JETTY_BASE"
( cd "$JETTY_BASE" && java -jar "${JETTY_HOME}/start.jar" \
    --add-modules=server,http,deploy,jsp,annotations,websocket-jakarta \
    --approve-all-licenses >/dev/null )

# Deployed as ROOT so the UI lives at / — the desktop launcher opens the bare
# host:port with no path.
cp -f "$PLANTUML_SERVER_WAR" "${JETTY_BASE}/webapps/ROOT.war"

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
cd /opt/plantuml/jetty-base
exec java -jar /opt/plantuml/jetty-home/start.jar "jetty.http.port=$PORT"
STARTER
sed -i "s/__PLANTUML_PORT__/${PLANTUML_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
# Register a desktop icon that opens the PlantUML server in a browser
# (desktop variants only).
# PlantUML's own favicon lives at the root of the war; extract it so the launcher
# carries upstream's mark instead of a generic globe. Falls back to a themed icon
# when the war layout changes or unzip is unavailable.
ICON="applications-graphics"
if command -v unzip >/dev/null 2>&1 \
   && unzip -p "$PLANTUML_SERVER_WAR" favicon.ico > "${PLANTUML_DIR}/favicon.ico" 2>/dev/null \
   && [ -s "${PLANTUML_DIR}/favicon.ico" ]; then
  ICON="${PLANTUML_DIR}/favicon.ico"
else
  rm -f "${PLANTUML_DIR}/favicon.ico"
fi
cb-web-icon.sh --id plantuml --name "PlantUML" --icon "$ICON" \
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
