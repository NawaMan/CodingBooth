#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --expose 21200 --select n8n+expose+autostart+persist+sandbox+search

# n8n Assistant code sandbox (needs Docker / dind). Runs before +autostart:
# the settings n8n reads are written now, the containers start in the background.
if start-n8n-sandbox --env-only; then
  nohup bash -c 'for _ in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done; start-n8n-sandbox' \
    > /tmp/n8n-sandbox.log 2>&1 &
  echo "n8n sandbox service starting (PID $!, log: /tmp/n8n-sandbox.log)"
else
  echo "⚠️  Could not write the n8n sandbox settings; the Assistant will have no code sandbox."
fi
