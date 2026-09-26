#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Notebook Web Preview: the wrapper's nginx gates /proxy/<port>/ on the Jupyter
# login and proxies to the booth port itself, with Jupyter's cookies removed.
# The fixture servers are the same ones test027 previews through code-server.
set -euo pipefail
source ../common--source.sh
NAME="notebook-preview-test-$RANDOM"
PORT="$(pick_free_port)"
WORK="$(mktemp -d)"
mkdir -p "$WORK/.booth"
cp fixtures/web-preview/server.py "$WORK/"
cp -R fixtures/web-preview/.booth/startups "$WORK/.booth/"
# What the Markdown Viewer renders (viewmd serves the booth's code folder).
printf '# Preview fixture\n\nRendered by viewmd for the notebook preview.\n' >"$WORK/README.md"
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
run_coding_booth --variant notebook --code "$WORK" --name "$NAME" --port "$PORT" --public --daemon >"$0.log" 2>&1
ready=false
for _ in {1..90}; do
  if [[ "$(fetch -o /dev/null -w '%{http_code}' "$BASE/login" || true)" == 200 ]]; then ready=true; break; fi
  sleep 1
done
check 1 "$ready" "Password-protected JupyterLab is ready"

code=$(fetch -o /dev/null -w '%{http_code}' "$BASE/proxy/8080/api/id")
check 2 "$([[ "$code" == 401 || "$code" == 403 ]] && echo true || echo false)" "Anonymous preview API is denied (got $code)"

# Jupyter's login form: the _xsrf cookie from the GET is echoed in the POST.
fetch -c "$WORK/cookies" -o /dev/null "$BASE/login"
xsrf=$(awk '$6 == "_xsrf" { print $7 }' "$WORK/cookies")
fetch -b "$WORK/cookies" -c "$WORK/cookies" -o /dev/null \
  --data-urlencode "password=$PASSWORD" --data-urlencode "_xsrf=$xsrf" "$BASE/login"
html=$(fetch --compressed -b "$WORK/cookies" -D "$WORK/headers" "$BASE/proxy/8080/")
check 3 "$([[ "$html" == *'src="/proxy/8080/assets/app.js"'* && "$html" == *'href="/proxy/8080/assets/app.css"'* ]] && echo true || echo false)" "HTML assets stay on the preview's port, including compressed responses"
check 4 "$(if ! grep -qiE '^(X-Frame-Options|Content-Security-Policy):' "$WORK/headers"; then echo true; else echo false; fi)" "Application frame-blocking headers are removed"
script=$(fetch -b "$WORK/cookies" "$BASE/proxy/8080/assets/app.js")
check 5 "$([[ "$script" == *'fetch("/proxy/8080/api/id")'* ]] && echo true || echo false)" "JavaScript API URLs are rewritten"

# The Jupyter session (username-*) and _xsrf are removed; the app's own survives.
case_no=6
for port in 8080 8081; do
  body=$(fetch -b "$WORK/cookies" -b "app=keep" "$BASE/proxy/$port/api/id")
  check "$case_no" "$([[ "$body" == *"\"port\": $port"* && "$body" == *'"cookie": "app=keep"'* ]] && echo true || echo false)" "Port $port reaches its own server with only the app's cookie (got: $body)"
  case_no=$((case_no + 1))
done
for path in redirect absolute-redirect; do
  headers=$(fetch -b "$WORK/cookies" -D - -o /dev/null "$BASE/proxy/8080/$path")
  check "$case_no" "$([[ "$headers" == *'/proxy/8080/next'* && "$headers" != *'/proxy/8080/proxy/'* ]] && echo true || echo false)" "$path remains inside the preview without a doubled prefix"
  case_no=$((case_no + 1))
done

socket=$(fetch --http1.1 -N --max-time 5 -b "$WORK/cookies" -i \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  "$BASE/proxy/8080/ws" || true)
check 10 "$([[ "$socket" == *" 101 "* && "$socket" == *'socket-8080'* ]] && echo true || echo false)" "WebSockets reach the preview's server"

controls=$(fetch -o /dev/null -w '%{http_code}' "$BASE/booth-preview/index.html")
check 11 "$([[ "$controls" == 200 ]] && echo true || echo false)" "Preview controls are served (got $controls)"
servers=$(fetch -b "$WORK/cookies" "$BASE/server-proxy/servers-info")
check 12 "$([[ "$servers" == *'"booth-web-preview"'* && "$servers" == *'"booth-markdown-viewer"'* && "$servers" == *'booth-preview/index.html'* && "$servers" != *'"new_browser_tab": true'* ]] && echo true || echo false)" "JupyterLab Launcher lists Web Preview and Markdown Viewer, both opening in JupyterLab tabs"

# Markdown Viewer: viewmd starts on demand, then is served behind the login.
fetch -X POST -o /dev/null "$BASE/booth-messages/api/viewmd"
code=$(fetch -o /dev/null -w '%{http_code}' "$BASE/proxy/8765/")
viewmd=$(fetch -b "$WORK/cookies" "$BASE/proxy/8765/")
check 13 "$([[ ( "$code" == 401 || "$code" == 403 ) && "$viewmd" == *'<title>viewmd</title>'* && "$viewmd" == *'src="/proxy/8765/vendor/marked.umd.js"'* ]] && echo true || echo false)" "viewmd starts on demand and is served, rewritten, only after login (anonymous: $code)"

# Every open page polls /__booth/health; on Jupyter's "/" that was an INFO
# "302 GET /" line per probe. The notebook probes /api, which Jupyter logs at
# debug level only.
before=$(docker logs "$NAME" 2>&1 | grep -c ' GET / (' || true)
for _ in 1 2 3 4 5; do fetch -o /dev/null "$BASE/__booth/health"; done
# /api answers 200 itself, so the body is Jupyter's version JSON rather than
# "ok <time>" (see docs/BOOTH_HEALTH.md); callers read the status and header.
health=$(fetch -o /dev/null -D - -w '%{http_code}' "$BASE/__booth/health")
sleep 1
after=$(docker logs "$NAME" 2>&1 | grep -c ' GET / (' || true)
check 14 "$([[ "$health" == *200 && "$health" == *[Xx]-[Bb]ooth-[Ii]nstance:* && "$after" == "$before" ]] && echo true || echo false)" "Health probes answer 200 with the instance id, without logging a line each (GET / lines: $before -> $after)"

# Browser tests are capability-gated, as in test027 (CB_PLAYWRIGHT_MODULE,
# CB_CHROMIUM_PATH name the package and browser when not on the usual paths).
if command -v node >/dev/null && node -e 'require(process.env.CB_PLAYWRIGHT_MODULE || "playwright")' >/dev/null 2>&1; then
  CB_PREVIEW_TEST_PASSWORD="$PASSWORD" node fixtures/web-preview/browser-notebook.cjs "$BASE"
  check 15 true "Launcher tiles and ＋ open preview tabs in JupyterLab that preview booth servers and Markdown and restore after a reload, in Chromium"
else
  echo "SKIP: browser checks require Node and the playwright package (CB_PLAYWRIGHT_MODULE may name its path)."
fi
