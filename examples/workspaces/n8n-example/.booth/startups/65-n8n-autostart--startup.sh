#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --expose 21200 --select n8n+expose+autostart+persist+sandbox+search

# Auto-start n8n in background
PORT=${N8N_PORT:-21200}
LOG_FILE="/tmp/n8n.log"

nohup start-n8n "$PORT" > "$LOG_FILE" 2>&1 &

echo "n8n started on port $PORT (PID $!, log: $LOG_FILE)"
