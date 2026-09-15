#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select shell-history/anythingllm+expose+autostart+project-fs+passwordless

# Auto-start AnythingLLM in background
PORT=${ANYTHINGLLM_PORT:-3001}
LOG_FILE="/tmp/anythingllm.log"

nohup start-anythingllm "$PORT" > "$LOG_FILE" 2>&1 &

echo "AnythingLLM started on port $PORT (PID $!, log: $LOG_FILE)"
