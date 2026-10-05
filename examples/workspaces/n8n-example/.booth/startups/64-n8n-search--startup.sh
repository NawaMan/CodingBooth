#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --expose 21200 --select n8n+expose+autostart+persist+sandbox+search

# n8n Assistant web search: SearXNG (needs Docker / dind). start-n8n already
# knows the URL from N8N_SEARXNG_PORT; the container starts in the background.
nohup bash -c 'for _ in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done; start-n8n-search' \
  > /tmp/n8n-search.log 2>&1 &
echo "SearXNG starting (PID $!, log: /tmp/n8n-search.log)"
