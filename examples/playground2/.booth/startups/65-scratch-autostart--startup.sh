#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant desktop-xfce --port 10000 --select python+pip-config+vscode-ext/java+vscode-ext/nodejs+npmrc+vscode-ext/notebook/codeserver+settings-cache/thonny/scratch+expose+autostart/exercism/bluej/greenfoot/drracket/nbgrader

# Auto-start Scratch editor in background
PORT=${SCRATCH_PORT:-18601}
LOG_FILE="/tmp/scratch.log"

nohup serve -s --no-clipboard /opt/scratch -l "$PORT" > "$LOG_FILE" 2>&1 &

echo "Scratch started on port $PORT (PID $!, log: $LOG_FILE)"
