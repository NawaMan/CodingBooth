#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# First-five-minutes AFFiNE demo: wait for the self-hosted UI, then print the URL.
set -euo pipefail

PORT="${AFFINE_SERVER_PORT:-13010}"
URL="http://127.0.0.1:${PORT}/"
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

echo "Waiting for AFFiNE Server on ${URL} ..."

up=0
code=""
for _ in $(seq 1 90); do
  # Follow redirects: a fresh instance 302s to /admin/setup (create first account).
  code="$(curl -sS -L --max-redirs 5 -o "$BODY" -w '%{http_code}' --max-time 5 "$URL" 2>/dev/null || true)"
  if [[ "$code" =~ ^(200|301|302|303|307|308)$ ]]; then
    up=1
    break
  fi
  sleep 2
done

if [[ "$up" -ne 1 ]]; then
  echo "❌ AFFiNE Server did not become ready on ${URL}" >&2
  echo "   Is autostart on? Try: start-affine-server ${PORT}" >&2
  echo "   Log: /tmp/affine-server.log" >&2
  exit 1
fi

# SPA, first-run admin setup, or the 302 Location all name Affine.
if ! grep -qiE 'affine|admin/setup' "$BODY"; then
  echo "❌ ${URL} answered HTTP ${code} but the page did not look like AFFiNE." >&2
  exit 1
fi

echo "---"
echo "AFFiNE Server is up at ${URL} (HTTP ${code})"
echo "Open that URL and create the first account — it becomes the admin."
echo "✅ AFFiNE Server is up."
