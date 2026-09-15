#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select shell-history/anythingllm+expose+autostart+project-fs+passwordless

# Strip a persisted instance password before autostart (65) loads .env.
for f in /opt/anythingllm/server/.env "${STORAGE_DIR:-$HOME/.anythingllm}/.env"; do
  [ -f "$f" ] || continue
  if grep -q '^AUTH_TOKEN=' "$f"; then
    grep -v '^AUTH_TOKEN=' "$f" > "${f}.cb-nopw" && mv "${f}.cb-nopw" "$f"
    echo "AnythingLLM passwordless: removed AUTH_TOKEN from $f"
  fi
done
