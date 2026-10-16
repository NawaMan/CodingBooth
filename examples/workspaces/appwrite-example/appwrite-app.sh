#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Prepare the booth's Appwrite for starter-for-svelte: sign in as the console
# admin, create a team, a project and a localhost web platform (each skipped
# when it already exists), then write starter-for-svelte/.env so the browser
# talks to this booth's Appwrite instead of Appwrite Cloud.
set -euo pipefail

cd "$(dirname "$0")"

PORT="${APPWRITE_PORT:-8080}"
API="http://127.0.0.1:${PORT}/v1"
EMAIL="${APPWRITE_ADMIN_EMAIL:-admin@example.com}"
PASSWORD="${APPWRITE_ADMIN_PASSWORD:-password123}"
TEAM_ID="starter-team"
PROJECT_ID="${STARTER_PROJECT_ID:-starter}"
PROJECT_NAME="Svelte starter"

# The browser runs on the host, so .env needs host-side ports. They are the
# booth port minus the offsets in .booth/config.toml (+-1920:8080, +-4827:5173).
BOOTH_PORT="${BOOTH_PORT:-10000}"
APPWRITE_HOST_PORT="${APPWRITE_HOST_PORT:-$((BOOTH_PORT - 1920))}"
WEB_HOST_PORT="${WEB_HOST_PORT:-$((BOOTH_PORT - 4827))}"

COOKIES="$(mktemp)"
BODY="$(mktemp)"
trap 'rm -f "$COOKIES" "$BODY"' EXIT

echo "=== Waiting for Appwrite on :${PORT} ==="
for _ in $(seq 1 120); do
  curl -fsS -m 3 -H "Host: localhost" "${API}/health/version" >/dev/null 2>&1 && break
  sleep 5
done
if ! curl -fsS -m 3 -H "Host: localhost" "${API}/health/version" >/dev/null 2>&1; then
  echo "❌ Appwrite did not become ready. Try: start-appwrite (log: /tmp/appwrite-server.log)" >&2
  exit 1
fi

# console_post <what> <path> <json> — POST as the console admin. 201 = created,
# 409 = already there (a +persist/+seed database, or a second run).
console_post() {
  local what="$1" path="$2" json="$3" code
  code="$(curl -sS -m 120 -o "$BODY" -w '%{http_code}' -b "$COOKIES" -c "$COOKIES" \
    -X POST "${API}${path}" \
    -H "Host: localhost" \
    -H "Content-Type: application/json" \
    -H "X-Appwrite-Project: console" \
    -d "$json" || echo 000)"
  case "$code" in
    200|201) echo "  ${what}: created" ;;
    409)     echo "  ${what}: already there" ;;
    *)
      echo "❌ ${what}: HTTP ${code}" >&2
      cat "$BODY" >&2; echo >&2
      exit 1
      ;;
  esac
}

echo "=== Preparing project '${PROJECT_ID}' as ${EMAIL} ==="
# start-appwrite creates the admin only after the health check passes, so on a
# fresh booth the sign-in can briefly answer 401. Wait for the account.
for _ in $(seq 1 60); do
  code="$(curl -sS -m 30 -o "$BODY" -w '%{http_code}' -c "$COOKIES" \
    -X POST "${API}/account/sessions/email" \
    -H "Host: localhost" \
    -H "Content-Type: application/json" \
    -H "X-Appwrite-Project: console" \
    -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}" || true)"
  [[ "$code" == "201" ]] && break
  sleep 5
done
if [[ "$code" != "201" ]]; then
  echo "❌ Could not sign in as ${EMAIL} (HTTP ${code})." >&2
  cat "$BODY" >&2; echo >&2
  echo "   The admin is created by start-appwrite — see /tmp/appwrite-server.log." >&2
  exit 1
fi
echo "  session: signed in"
console_post "team"    "/teams" \
  "{\"teamId\":\"${TEAM_ID}\",\"name\":\"Starter\"}"
console_post "project"  "/projects" \
  "{\"projectId\":\"${PROJECT_ID}\",\"name\":\"${PROJECT_NAME}\",\"teamId\":\"${TEAM_ID}\"}"
console_post "platform" "/projects/${PROJECT_ID}/platforms" \
  "{\"platformId\":\"localhost-web\",\"type\":\"web\",\"name\":\"localhost\",\"hostname\":\"localhost\"}"

cat > starter-for-svelte/.env <<EOF
PUBLIC_APPWRITE_ENDPOINT=http://localhost:${APPWRITE_HOST_PORT}/v1
PUBLIC_APPWRITE_PROJECT_ID=${PROJECT_ID}
PUBLIC_APPWRITE_PROJECT_NAME="${PROJECT_NAME}"
EOF
echo "  .env: starter-for-svelte/.env → http://localhost:${APPWRITE_HOST_PORT}/v1"

# The same request the starter's "Send a ping" button makes, from the same origin.
pong="$(curl -sS -m 20 -H "Host: localhost" -H "X-Appwrite-Project: ${PROJECT_ID}" \
  -H "Origin: http://localhost:${WEB_HOST_PORT}" "${API}/ping" || true)"
if [[ "$pong" != "Pong!" ]]; then
  echo "❌ Ping from http://localhost:${WEB_HOST_PORT} was refused: ${pong}" >&2
  exit 1
fi
echo "  ping: ${pong}"
echo "✅ Appwrite project ready for starter-for-svelte."
