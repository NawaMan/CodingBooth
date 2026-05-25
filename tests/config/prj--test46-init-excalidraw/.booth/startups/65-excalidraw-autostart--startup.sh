#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select excalidraw:889+expose+autostart

# Auto-start Excalidraw in background
PORT=${EXCALIDRAW_PORT:-889}
LOG_FILE="/tmp/excalidraw.log"

nohup serve -s --no-clipboard /opt/excalidraw -l "$PORT" > "$LOG_FILE" 2>&1 &

echo "Excalidraw started on port $PORT (PID $!, log: $LOG_FILE)"
