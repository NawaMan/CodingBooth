#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --port 10000 --select nodejs+npmrc+vscode-ext/bun+vscode-ext/excalidraw+autostart/claude-code+auto-accept+credential+settings-cache

# Auto-start Excalidraw in background
PORT=${EXCALIDRAW_PORT:-15555}
LOG_FILE="/tmp/excalidraw.log"

nohup serve -s --no-clipboard /opt/excalidraw -l "$PORT" > "$LOG_FILE" 2>&1 &

echo "Excalidraw started on port $PORT (PID $!, log: $LOG_FILE)"
