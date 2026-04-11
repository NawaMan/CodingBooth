#!/bin/bash
set -e
# Configured by: booth init adjust --select mermaid:11.4.2,19190+expose+autostart

# Auto-start Mermaid Live Editor in background
PORT=${MERMAID_PORT:-19190}
LOG_FILE="/tmp/mermaid.log"

nohup serve -s --no-clipboard /opt/mermaid -l "$PORT" > "$LOG_FILE" 2>&1 &

echo "Mermaid Live Editor started on port $PORT (PID $!, log: $LOG_FILE)"
