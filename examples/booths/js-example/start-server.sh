#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Starts the API server and Vite dev server as daemons with configurable runtime.

set -euo pipefail

API_PID_FILE="$HOME/.dev_api_server.pid"
API_LOG_FILE="$HOME/.dev_api_server.log"
VITE_PID_FILE="$HOME/.dev_vite_server.pid"
VITE_LOG_FILE="$HOME/.dev_vite_server.log"

runtime="npm"
for arg in "$@"; do
    case $arg in
        --runtime=*)
            runtime="${arg#--runtime=}"
            ;;
        *)
            echo "Usage: start-server.sh [--runtime=NAME]"
            exit 1
            ;;
    esac
done

# Determine API server command based on runtime
api_cmd=""
case "$runtime" in
    bun)   api_cmd="bun run server/index.ts" ;;
    deno)
        if [[ -f deno.json ]]; then
            main=$(jq -r '.main // empty' deno.json)
        fi
        main="${main:-server/index.ts}"
        api_cmd="deno run --allow-net --allow-read --allow-env $main"
        ;;
    node|npm|*) api_cmd="npx tsx server/index.ts" ;;
esac

# Vite always runs with npm (it's a Node.js tool)
vite_cmd="npx vite"

# Start API server in its own session/process group
setsid bash -c "exec $api_cmd" > "$API_LOG_FILE" 2>&1 &
api_pid=$!
echo "$api_pid" > "$API_PID_FILE"
echo "🚀 Started API server with $runtime (PID: $api_pid). Log → $API_LOG_FILE"

# Start Vite dev server in its own session/process group
setsid bash -c "exec $vite_cmd" > "$VITE_LOG_FILE" 2>&1 &
vite_pid=$!
echo "$vite_pid" > "$VITE_PID_FILE"
echo "🚀 Started Vite dev server (PID: $vite_pid). Log → $VITE_LOG_FILE"
