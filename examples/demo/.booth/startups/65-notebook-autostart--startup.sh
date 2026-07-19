#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant xfce --port NEXT:22000 --expose +333 --env GEOMETRY=1920x1080 --env GOOGLE_APPLICATION_CREDENTIALS=/home/coder/.config/gcloud/application_default_credentials.json --env GNOME_KEYRING_CONTROL= --env GNOME_KEYRING_PID= --env SSH_AUTH_SOCK= --mount ~/.config/Antigravity:/etc/cb-home-seed/.config/Antigravity:ro --mount ~/.antigravity:/etc/cb-home-seed/.antigravity:ro --mount ~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro --mount ~/.config/github-copilot:/etc/cb-home-seed/.config/github-copilot:ro --mount ~/.claude/settings.json:/etc/cb-home-seed/.claude/settings.json:ro --mount ~/.codex/auth.json:/etc/cb-home-seed/.codex/auth.json:ro --select go:1.25.4+vscode-ext/python:3.12+pip-config+vscode-ext+pip-pkg:matplotlib,psycopg2-binary/java+vscode-ext+kernel-jjava+m2+maven+gradle+jbang/nodejs:20+npmrc+vscode-ext/postgresql/notebook+expose:${NOTEBOOK_PORT:-+8888}+autostart/bash-nb-kernel/pycharm/dbeaver/claude-code+credential+settings-cache

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
