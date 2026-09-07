#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select appwrite-server+autostart+expose

# Auto-start self-hosted Appwrite (needs Docker / dind).
PORT=${APPWRITE_PORT:-8080}
LOG_FILE="/tmp/appwrite-server.log"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker info >/dev/null 2>&1; then
  echo "⚠️  Docker is not available; cannot auto-start Appwrite (select dind)."
else
  nohup start-appwrite > "$LOG_FILE" 2>&1 &
  echo "Appwrite starting on port $PORT (PID $!, log: $LOG_FILE)"
fi
