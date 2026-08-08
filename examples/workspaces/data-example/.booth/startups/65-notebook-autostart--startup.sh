#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant xfce --port NEXT:24000 --expose +3000:13000 --select python:3.12+pip-pkg:matplotlib,psycopg2-binary/nodejs:20/postgresql/notebook+expose:+8888+autostart/dbeaver/sales-explorer

# Auto-start JupyterLab in background.
# The notebook variant already runs JupyterLab as its primary service on this
# same port (start-notebook-wrapped), so starting another one would collide.
if [ "${BOOTH_VARIANT_TAG:-base}" = "notebook" ]; then
  echo "JupyterLab is the primary service of the notebook variant — auto-start skipped."
else
  PORT=${NOTEBOOK_PORT:-18888}
  LOG_FILE="/tmp/notebook.log"

  nohup start-notebook "$PORT" > "$LOG_FILE" 2>&1 &

  echo "JupyterLab started on port $PORT (PID $!, log: $LOG_FILE)"
fi
