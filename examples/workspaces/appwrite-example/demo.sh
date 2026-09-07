#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# First-five-minutes Appwrite demo: the CLI is on PATH, the self-hosted
# console answers /v1/health/version, and the CLI is pointed at it.
set -euo pipefail

PORT="${APPWRITE_PORT:-8080}"
# 8080 = current template default. 80 = official installer default when the
# HTTP port flag is ignored. Try the configured port first.
CANDIDATES=("$PORT")
[[ "$PORT" != "80" ]] && CANDIDATES+=("80")
[[ "$PORT" != "8080" ]] && CANDIDATES+=("8080")

echo "=== Appwrite CLI ==="
if ! command -v appwrite >/dev/null 2>&1; then
  echo "❌ appwrite CLI is not on PATH. Select appwrite-cli (appwrite-server requires it)." >&2
  exit 1
fi
appwrite -v
echo

echo "=== Waiting for Appwrite server (ports: ${CANDIDATES[*]}) ==="
echo "(first boot pulls the Compose stack — several minutes)"

ready_port=""
body=""
for i in $(seq 1 120); do
  for p in "${CANDIDATES[@]}"; do
    if body="$(curl -fsS -m 3 -H "Host: localhost" \
         "http://127.0.0.1:${p}/v1/health/version" 2>/dev/null)"; then
      ready_port="$p"
      break 2
    fi
  done
  sleep 5
done

if [[ -z "$ready_port" ]]; then
  echo "❌ Appwrite did not become ready. Is autostart on, and is Docker (dind) up?" >&2
  echo "   Try: start-appwrite" >&2
  echo "   Log: /tmp/appwrite-server.log" >&2
  exit 1
fi

ENDPOINT="http://localhost:${ready_port}/v1"
echo "--- health (:${ready_port}) ---"
echo "$body"
echo

echo "=== Point the CLI at the local server ==="
appwrite client --endpoint "$ENDPOINT" --self-signed true
appwrite client --debug || true

echo
echo "Console: http://localhost:${ready_port}"
echo "✅ Appwrite CLI and server are both working."
