#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Run Appwrite's Svelte starter against this booth's Appwrite: prepare the
# project, install the starter's packages, then serve it with Vite on :5173.
set -euo pipefail

cd "$(dirname "$0")"
./appwrite-app.sh

cd starter-for-svelte
[[ -d node_modules ]] || npm ci

HOST_PORT="${BOOTH_HOST_PORT:-10000}"   # resolved; BOOTH_PORT may be NEXT or RANDOM
echo
echo "Open http://localhost:${WEB_HOST_PORT:-$((HOST_PORT - 4827))} and press \"Send a ping\". Ctrl+C stops it."
echo "  or http://localhost:${HOST_PORT}/proxy/5173/  (through the booth port)"
exec npx vite dev --host 0.0.0.0 --port 5173 --strictPort
