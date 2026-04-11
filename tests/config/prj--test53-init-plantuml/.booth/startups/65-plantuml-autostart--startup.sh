#!/bin/bash
set -e
# Configured by: booth init adjust --select plantuml:1.2025.2,19090+expose+autostart

# Auto-start PlantUML Server in background
PORT=${PLANTUML_PORT:-19090}
LOG_FILE="/tmp/plantuml-server.log"

nohup java -jar /opt/plantuml/jetty/jetty-runner.jar --port "$PORT" /opt/plantuml/plantuml-server.war > "$LOG_FILE" 2>&1 &

echo "PlantUML Server started on port $PORT (PID $!, log: $LOG_FILE)"
