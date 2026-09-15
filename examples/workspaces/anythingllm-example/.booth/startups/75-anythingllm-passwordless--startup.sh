#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select shell-history/anythingllm+expose+autostart+project-fs+passwordless

# If the server is already up with a password from this session, turn it off.
PORT=${ANYTHINGLLM_PORT:-3001}
export PORT
(
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/ping" >/dev/null 2>&1 && break
    sleep 2
  done
  curl -fsS -X POST "http://127.0.0.1:$PORT/api/system/update-password" \
    -H "Content-Type: application/json" \
    -d '{"usePassword":false}' \
    && echo "AnythingLLM passwordless: password protection disabled"
) >/tmp/anythingllm-passwordless.log 2>&1 &
echo "AnythingLLM passwordless: AUTH_TOKEN left empty (log: /tmp/anythingllm-passwordless.log)"
