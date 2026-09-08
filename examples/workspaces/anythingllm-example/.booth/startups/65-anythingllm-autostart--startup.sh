#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select anythingllm+autostart+expose+project-fs+passwordless

# Auto-start AnythingLLM in background
PORT=${ANYTHINGLLM_PORT:-3001}
LOG_FILE="/tmp/anythingllm.log"

nohup start-anythingllm "$PORT" > "$LOG_FILE" 2>&1 &

echo "AnythingLLM started on port $PORT (PID $!, log: $LOG_FILE)"
