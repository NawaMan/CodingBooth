#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant xfce --select python~vscode-ext/thonny/apt-pkg:tk,xvfb/nodejs~vscode-ext/logo+autostart+expose

# Auto-start Logo editor in background
PORT=${LOGO_PORT:-18610}
LOG_FILE="/tmp/logo.log"

nohup serve -s --no-clipboard /opt/logo -l "$PORT" > "$LOG_FILE" 2>&1 &

echo "Logo started on port $PORT (PID $!, log: $LOG_FILE)"
