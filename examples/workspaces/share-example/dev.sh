#!/bin/bash
# Start the app for development: the API (:3001) and the front end (:8080),
# both under `node --watch`, so editing a server file restarts it. Front-end
# files in web/public/ are read fresh on every request; just reload the page.
# Ctrl+C stops both.
set -euo pipefail
cd "$(dirname "$0")"

export API_PORT="${API_PORT:-3001}" WEB_PORT="${WEB_PORT:-8080}"

pids=()
trap 'pkill -f "node --watch (api|web)/server.js" 2>/dev/null; kill "${pids[@]}" 2>/dev/null || true' EXIT INT TERM

node --watch api/server.js 2>&1 | sed -u 's/^/[api] /' & pids+=($!)
node --watch web/server.js 2>&1 | sed -u 's/^/[web] /' & pids+=($!)

echo "App: http://localhost:$WEB_PORT in the booth (API: :$API_PORT/api/notes); from the host: just ports"
echo "Share it from another terminal: just share-web   (or just share-api)"
wait
