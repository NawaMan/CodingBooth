#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# How many pings has the starter project received? Appwrite keeps the count on
# the project itself (pingCount, pingedAt), readable only by the console admin —
# so sign in as the admin and read the project. This is the exact total, unlike
# the console's Requests chart, which is a delayed usage statistic.
set -euo pipefail

PORT="${APPWRITE_PORT:-8080}"
API="http://127.0.0.1:${PORT}/v1"
EMAIL="${APPWRITE_ADMIN_EMAIL:-admin@example.com}"
PASSWORD="${APPWRITE_ADMIN_PASSWORD:-password123}"
PROJECT_ID="${STARTER_PROJECT_ID:-starter}"

COOKIES="$(mktemp)"
BODY="$(mktemp)"
trap 'rm -f "$COOKIES" "$BODY"' EXIT

code="$(curl -sS -m 30 -o "$BODY" -w '%{http_code}' -c "$COOKIES" \
  -X POST "${API}/account/sessions/email" \
  -H "Host: localhost" \
  -H "Content-Type: application/json" \
  -H "X-Appwrite-Project: console" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}" || echo 000)"
if [[ "$code" != "201" ]]; then
  echo "❌ Could not sign in as ${EMAIL} (HTTP ${code}). Is Appwrite up? Try: just run" >&2
  exit 1
fi

code="$(curl -sS -m 30 -o "$BODY" -w '%{http_code}' -b "$COOKIES" \
  "${API}/projects/${PROJECT_ID}" \
  -H "Host: localhost" \
  -H "X-Appwrite-Project: console" || echo 000)"
case "$code" in
  200) ;;
  404)
    echo "❌ No project '${PROJECT_ID}' yet. Create it with: just app" >&2
    exit 1
    ;;
  *)
    echo "❌ Reading project '${PROJECT_ID}': HTTP ${code}" >&2
    cat "$BODY" >&2; echo >&2
    exit 1
    ;;
esac

count="$(jq -r '.pingCount // 0' "$BODY")"
pinged="$(jq -r '.pingedAt // ""' "$BODY")"
[[ -n "$pinged" ]] && pinged="$(date -d "$pinged" '+%F %T %Z')" || pinged="never"

echo "Project:   ${PROJECT_ID}"
echo "pingCount: ${count}"
echo "pingedAt:  ${pinged}"
