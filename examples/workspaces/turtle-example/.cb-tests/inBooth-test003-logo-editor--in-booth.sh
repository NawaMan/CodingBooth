#!/bin/bash
# The Logo editor is the root-installed catalog server (/opt/logo + start-logo),
# not anything under the project mount (/home/coder/code).
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=18610
echo "=== Testing catalog Logo server at /opt/logo ==="

test -x /usr/local/bin/start-logo
test "$(command -v start-logo)" = /usr/local/bin/start-logo
test -f /opt/logo/index.html
test ! -e /home/coder/code/logo/index.html
test ! -e /home/coder/code/start-logo
test ! -e /home/coder/code/start-logo.sh

if ! curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/"; then
  start-logo "$PORT" >/tmp/logo-editor-test.log 2>&1 &
  server_pid=$!
  trap 'kill "$server_pid" 2>/dev/null || true' EXIT
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/"; then
      break
    fi
    sleep 0.2
  done
fi

page="$(curl -sf --max-time 5 "http://127.0.0.1:${PORT}/")"
echo "$page" | grep -q "Logo Interpreter"
echo "$page" | grep -q "vendor/codemirror/codemirror.min.js"
echo "$page" | grep -q 'id="open-file"'
echo "$page" | grep -q 'Open file'
test -f samples/square.logo
grep -q hideturtle samples/square.logo
curl -sf --max-time 5 "http://127.0.0.1:${PORT}/examples.txt" | grep -q 'samples/square.logo'

# The process on 18610 must be `serve … /opt/logo`, not a project-tree http.server.
serve_cmd="$(pgrep -af '[s]erve' || true)"
echo "serve process: ${serve_cmd}"
echo "$serve_cmd" | grep -q '/opt/logo'
if echo "$serve_cmd" | grep -q '/home/coder/code'; then
  echo "Logo is being served from the project tree; want /opt/logo"
  exit 1
fi
if pgrep -af '[h]ttp.server' | grep -q '/home/coder/code'; then
  echo "python http.server is serving the project tree"
  exit 1
fi

already="$(start-logo "$PORT")"
echo "$already"
echo "$already" | grep -q "already running"

# On desktop variants, Excalidraw-style launcher must be on the desktop.
if /opt/codingbooth/setups/cb-has-desktop.sh; then
  test -f /usr/share/applications/logo-web.desktop
  test -f /etc/cb-web-services/logo.conf
  test -f /etc/skel/Desktop/logo-web.desktop
  grep -q 'Exec=cb-web-open logo' /usr/share/applications/logo-web.desktop
  echo "Logo desktop icon registered"
fi

echo "Logo editor is the root-installed /opt/logo server"
