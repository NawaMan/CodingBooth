#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Real authenticated code-server proxy, plus browser tests when Playwright exists.
set -euo pipefail
source ../common--source.sh
NAME="web-preview-test-$RANDOM"
PORT="$(pick_free_port)"
WORK="$(mktemp -d)"
mkdir -p "$WORK/.booth"
cp fixtures/web-preview/server.py "$WORK/"
cp -R fixtures/web-preview/.booth/startups "$WORK/.booth/"
PASSWORD="preview-test-$RANDOM"
printf '%s' "$PASSWORD" >"$WORK/.booth/.booth.password"
chmod 600 "$WORK/.booth/.booth.password"
cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
BASE="https://localhost:$PORT"
fetch() { curl -sk --max-time 15 "$@"; }
check() {
  local number="$1" result="$2" description="$3"
  print_test_result "$result" "$0" "$number" "$description"
  if [[ "$result" != true ]]; then
    [[ ! -f "$WORK/headers" ]] || cat "$WORK/headers" >&2
    printf '%s\n' "${html:-}" >&2
    docker logs --tail 15 "$NAME" >&2
  fi
  [[ "$result" == true ]]
}
run_coding_booth --variant codeserver --code "$WORK" --name "$NAME" --port "$PORT" --public --daemon >"$0.log" 2>&1
ready=false
for _ in {1..60}; do
  if [[ "$(fetch -o /dev/null -w '%{http_code}' "$BASE/login" || true)" == 200 ]]; then ready=true; break; fi
  sleep 1
done
check 1 "$ready" "Password-protected code-server is ready"
code=$(fetch -D "$WORK/anonymous-headers" -o /dev/null -w '%{http_code}' "$BASE/proxy/8080/api/id")
denied=false
if [[ "$code" == 401 || "$code" == 403 ]]; then denied=true; fi
if [[ "$code" == 302 ]] && grep -qiE '^location:.*login' "$WORK/anonymous-headers"; then denied=true; fi
check 2 "$denied" "Anonymous preview API is denied (got $code)"
fetch -c "$WORK/cookies" --data-urlencode "password=$PASSWORD" "$BASE/login" >/dev/null
html=$(fetch --compressed -b "$WORK/cookies" -D "$WORK/headers" "$BASE/proxy/8080/")
check 3 "$([[ "$html" == *'src="/proxy/8080/assets/app.js"'* && "$html" == *'href="/proxy/8080/assets/app.css"'* ]] && echo true || echo false)" "HTML assets stay on the preview's port, including compressed responses"
check 4 "$(if ! grep -qiE '^(X-Frame-Options|Content-Security-Policy):' "$WORK/headers"; then echo true; else echo false; fi)" "Application frame-blocking headers are removed"
script=$(fetch -b "$WORK/cookies" "$BASE/proxy/8080/assets/app.js")
check 5 "$([[ "$script" == *'fetch("/proxy/8080/api/id")'* ]] && echo true || echo false)" "JavaScript API URLs are rewritten"
case_no=6
for port in 8080 8081; do
  body=$(fetch -b "$WORK/cookies" "$BASE/proxy/$port/api/id")
  check "$case_no" "$([[ "$body" == *"\"port\": $port"* && "$body" == *'"cookie": ""'* ]] && echo true || echo false)" "Port $port reaches its own server without forwarding the editor session cookie"
  case_no=$((case_no + 1))
done
for path in redirect absolute-redirect; do
  headers=$(fetch -b "$WORK/cookies" -D - -o /dev/null "$BASE/proxy/8080/$path")
  check "$case_no" "$([[ "$headers" == *'/proxy/8080/next'* && "$headers" != *'/proxy/8080/proxy/'* ]] && echo true || echo false)" "$path remains inside the preview without a doubled prefix"
  case_no=$((case_no + 1))
done

# Browser tests are capability-gated, not opt-in. Point at an existing package
# using CB_PLAYWRIGHT_MODULE when it isn't on Node's normal module search path.
if command -v node >/dev/null && node -e 'require(process.env.CB_PLAYWRIGHT_MODULE || "playwright")' >/dev/null 2>&1; then
  CB_PREVIEW_TEST_PASSWORD="$PASSWORD" node fixtures/web-preview/browser.cjs "$BASE"
  check 10 true "Booth previews, external pages, Google searches, history, WebSockets and restoration work in Chromium"
else
  echo "SKIP: browser checks require Node and the playwright package (CB_PLAYWRIGHT_MODULE may name its path)."
fi
