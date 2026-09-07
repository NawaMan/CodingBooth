#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select nodejs:22/affine-server+autostart+expose

# Auto-start AFFiNE Server in background (after postgres/redis at level 50).
PORT=${AFFINE_SERVER_PORT:-13010}
LOG_FILE="/tmp/affine-server.log"

nohup start-affine-server "$PORT" > "$LOG_FILE" 2>&1 &

echo "AFFiNE Server starting on port $PORT (PID $!, log: $LOG_FILE)"
