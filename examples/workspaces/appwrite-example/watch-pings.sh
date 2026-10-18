#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Watch pings arrive at Appwrite. The API container logs every request as a
# block of "key value" lines (http.method, http.path, http.response.code); this
# follows that log and prints one line per /v1/ping. Run it beside the Svelte
# starter and press "Send a ping" — each click shows up here.
set -euo pipefail

CONTAINER="${APPWRITE_CONTAINER:-appwrite}"   # container_name in Appwrite's Compose file

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "❌ No '${CONTAINER}' container. Is Appwrite up? Try: just run" >&2
  exit 1
fi

echo "=== Pings received by Appwrite (since its container started). Ctrl+C stops. ==="

n=0
method=""
path=""
# --timestamps: Appwrite's own lines carry none. The sed drops its colour codes.
docker logs --follow --timestamps "$CONTAINER" 2>&1 \
  | stdbuf -oL sed 's/\x1b\[[0-9;]*m//g' \
  | while read -r ts key value _; do
      case "$key" in
        http.request)       method=""; path="" ;;
        http.method)        method="$value" ;;
        http.path)          path="$value" ;;
        http.response.code)
          if [[ "$path" == "/v1/ping" ]]; then
            n=$((n + 1))
            printf '#%-3s %s  %s %s → %s\n' "$n" "$(date -d "$ts" '+%T')" "$method" "$path" "$value"
          fi
          ;;
      esac
    done
