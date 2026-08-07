#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: the base UI's login page, on a password-protected booth.
#
# A password booth used to hand the browser ttyd's HTTP Basic challenge, whose
# username box is the browser's own and always empty. The gate now lives in
# nginx and the credential is collected by a page we serve, so:
#   1) an anonymous visitor is redirected to /login
#   2) that page prefills the username with "coder"
#   3) the redirect is relative — it must not name the container's own port
#   4) a pane is gated too, and does NOT answer with a Basic auth challenge
#   5) the message API is gated (shutdown used to be reachable anonymously)
#   6) a wrong password is refused
#   7) the right password mints a Secure session cookie...
#   8) ...which opens both the UI and a live terminal pane
#
# This runs the real --public path (Caddy TLS in front of nginx) because that
# is the only way PASSWORD reaches a booth in production, and because the proxy
# is exactly what makes test 3 worth having.
# -----------------------------------------------------------------------------

set -euo pipefail

source ../common--source.sh

function generate_name() {
  local name
  while :; do
    name=$(printf "base-ui-login-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

function is_port_free() {
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$p" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  elif command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$p )" 2>/dev/null | grep -q ":$p"
  else
    ! (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$p" >/dev/null 2>&1)
  fi
}

function random_free_port() {
  local port
  for i in {1..100}; do
    port=$((50000 + RANDOM % 10001))
    if is_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done
  echo "Failed to find free port in range 50000-60000 after 100 tries" >&2
  return 1
}

NAME="$(generate_name)"
PORT="$(random_free_port)"

# Quotes and a backslash on purpose: the password rides to the login endpoint
# inside a JSON body that a bash server parses, and it is spliced into an nginx
# config as a Basic credential. Both are places a naive quoting bug would show.
PASSWORD='t3st"P@ss\word'

WORK="$(mktemp -d)"
mkdir -p "$WORK/.booth"
printf 'variant = "base"\n' > "$WORK/.booth/config.toml"
printf '%s' "$PASSWORD" > "$WORK/.booth/.booth.password"
chmod 600 "$WORK/.booth/.booth.password"

JAR="$WORK/cookies.txt"
BASE="https://localhost:$PORT"

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm   "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# -k throughout: --public without --tls-cert uses Caddy's self-signed cert.
curl_booth() { curl -sk --max-time 20 "$@"; }

b64() { printf '%s' "$1" | base64 -w0; }

login_body() {
  printf '{"username_b64":"%s","password_b64":"%s"}' "$(b64 "$1")" "$(b64 "$2")"
}

run_coding_booth --code "$WORK" --name "$NAME" --port "$PORT" --public --daemon > "$0.log" 2>&1

# --- Wait for the container, then for the TLS front door to actually answer ---
for i in {1..30}; do
  if docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
    if docker exec "$NAME" id coder >/dev/null 2>&1; then
      break
    fi
  fi
  sleep 1
done

if ! docker inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
  print_test_result "false" "$0" "0" "Container '$NAME' failed to start"
  cat "$0.log" >&2
  exit 1
fi

READY=false
for i in {1..40}; do
  if [[ -n "$(curl_booth -o /dev/null -w '%{http_code}' "$BASE/login" 2>/dev/null | grep -E '^(200|302)$')" ]]; then
    READY=true
    break
  fi
  sleep 1
done

if [[ "$READY" != "true" ]]; then
  print_test_result "false" "$0" "0" "TLS front door on $PORT never answered"
  docker logs "$NAME" 2>&1 | tail -30 >&2
  exit 1
fi

# -------------------------------------------------------
# Test 1: an anonymous visitor is sent to the login page
# -------------------------------------------------------
ROOT_CODE=$(curl_booth -o /dev/null -w '%{http_code}' "$BASE/")
ROOT_TO=$(curl_booth -o /dev/null -w '%{redirect_url}' "$BASE/")
if [[ "$ROOT_CODE" == "302" && "$ROOT_TO" == */login ]]; then
  print_test_result "true" "$0" "1" "Anonymous / redirects to the login page"
else
  print_test_result "false" "$0" "1" "Anonymous / redirect (got: $ROOT_CODE -> ${ROOT_TO:-<none>})"
  exit 1
fi

# -------------------------------------------------------
# Test 2: the login page prefills the username — the whole point
# -------------------------------------------------------
LOGIN_HTML=$(curl_booth "$BASE/login")
if [[ "$LOGIN_HTML" == *'id="username"'*'value="coder"'* ]]; then
  print_test_result "true" "$0" "2" "Login page prefills the username with 'coder'"
else
  print_test_result "false" "$0" "2" "Login page username prefill missing"
  echo "$LOGIN_HTML" | head -40 >&2
  exit 1
fi

# -------------------------------------------------------
# Test 3: the redirect is relative, so it survives the TLS proxy and the
#         host port mapping. An absolute one would name 10000/10443 and
#         send the browser somewhere that does not exist.
# -------------------------------------------------------
if [[ "$ROOT_TO" == "$BASE/login" ]]; then
  print_test_result "true" "$0" "3" "Redirect keeps the published host port ($ROOT_TO)"
else
  print_test_result "false" "$0" "3" "Redirect leaked an internal port (got: $ROOT_TO, want: $BASE/login)"
  exit 1
fi

# -------------------------------------------------------
# Test 4: a pane is gated, and specifically NOT with a Basic challenge —
#         a WWW-Authenticate here is the native browser dialog coming back
# -------------------------------------------------------
PANE_HEADERS=$(curl_booth -D- -o /dev/null "$BASE/s1/")
PANE_CODE=$(printf '%s' "$PANE_HEADERS" | head -1)
if [[ "$PANE_CODE" == *302* ]] && ! printf '%s' "$PANE_HEADERS" | grep -qi 'www-authenticate'; then
  print_test_result "true" "$0" "4" "Pane /s1/ is gated without a Basic auth challenge"
else
  print_test_result "false" "$0" "4" "Pane /s1/ gating (got: $PANE_CODE)"
  printf '%s' "$PANE_HEADERS" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 5: the message API is behind the gate too. Anonymous shutdown was
#         reachable before the gate existed.
# -------------------------------------------------------
API_CODE=$(curl_booth -o /dev/null -w '%{http_code}' -X POST "$BASE/booth-messages/api/shutdown")
if [[ "$API_CODE" == "401" ]]; then
  print_test_result "true" "$0" "5" "Anonymous booth-message API is refused (401)"
else
  print_test_result "false" "$0" "5" "Anonymous API should be 401 (got: $API_CODE)"
  exit 1
fi

# -------------------------------------------------------
# Test 6: a wrong password is refused, and mints no cookie
# -------------------------------------------------------
BAD_HEADERS=$(curl_booth -D- -o /dev/null -X POST "$BASE/booth-messages/api/login" \
  -H 'Content-Type: application/json' -d "$(login_body coder "wrong-$PASSWORD")")
if printf '%s' "$BAD_HEADERS" | head -1 | grep -q 401 \
   && ! printf '%s' "$BAD_HEADERS" | grep -qi 'set-cookie'; then
  print_test_result "true" "$0" "6" "Wrong password is refused with no session cookie"
else
  print_test_result "false" "$0" "6" "Wrong password should 401 with no cookie"
  printf '%s' "$BAD_HEADERS" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 7: the right password mints the session cookie, marked Secure
#         because --public means the browser is on HTTPS
# -------------------------------------------------------
OK_HEADERS=$(curl_booth -D- -c "$JAR" -o /dev/null -X POST "$BASE/booth-messages/api/login" \
  -H 'Content-Type: application/json' -d "$(login_body coder "$PASSWORD")")
COOKIE_LINE=$(printf '%s' "$OK_HEADERS" | grep -i 'set-cookie' || true)
if printf '%s' "$OK_HEADERS" | head -1 | grep -q 200 \
   && [[ "$COOKIE_LINE" == *booth_auth=* && "$COOKIE_LINE" == *HttpOnly* && "$COOKIE_LINE" == *Secure* ]]; then
  print_test_result "true" "$0" "7" "Correct password mints a Secure, HttpOnly session cookie"
else
  print_test_result "false" "$0" "7" "Session cookie (got: ${COOKIE_LINE:-<none>})"
  printf '%s' "$OK_HEADERS" >&2
  exit 1
fi

# -------------------------------------------------------
# Test 8: the cookie opens the UI and a real terminal pane. ttyd's /token
#         only answers once the credential nginx injects has been accepted,
#         so a 200 here proves the upstream auth is wired, not just the gate.
# -------------------------------------------------------
UI_CODE=$(curl_booth -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/")
PANE_CODE=$(curl_booth -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/s1/")
TOKEN_CODE=$(curl_booth -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/s1/token")
if [[ "$UI_CODE" == "200" && "$PANE_CODE" == "200" && "$TOKEN_CODE" == "200" ]]; then
  print_test_result "true" "$0" "8" "Session cookie opens the UI and a live ttyd pane"
else
  print_test_result "false" "$0" "8" "Authenticated access (/=$UI_CODE /s1/=$PANE_CODE /s1/token=$TOKEN_CODE)"
  exit 1
fi

exit 0
