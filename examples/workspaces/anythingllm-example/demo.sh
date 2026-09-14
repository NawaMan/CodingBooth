#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# First-five-minutes AnythingLLM demo: the UI answers /api/ping.
set -euo pipefail

PORT="${ANYTHINGLLM_PORT:-3001}"

echo "=== Waiting for AnythingLLM on :${PORT} ==="
echo "(first boot copies a large image and may take several minutes)"

body=""
# 100 * 5s = ~8.3 minutes. First boot runs `prisma generate`/`migrate deploy`
# before the server answers at all, which can run past the old 60*5s=5min
# budget when the host is busy building other example images concurrently
# (see run-example-tests.sh's intermittent-under-load note).
for _ in $(seq 1 100); do
  if body="$(curl -fsS -m 3 "http://127.0.0.1:${PORT}/api/ping" 2>/dev/null)"; then
    break
  fi
  sleep 5
done

if [[ -z "$body" ]]; then
  echo "❌ AnythingLLM did not become ready. Is autostart on?" >&2
  echo "   Try: start-anythingllm" >&2
  echo "   Log: /tmp/anythingllm.log" >&2
  exit 1
fi

echo "--- /api/ping (:${PORT}) ---"
echo "$body"
echo
echo "✅ AnythingLLM is up."
echo
echo "UI (host tab):   http://localhost:${PORT}"
echo "UI (globe pane): http://booth:${PORT}/"
echo
echo "The SPA basename follows the page URL: / on the host, /proxy/${PORT}"
echo "in the globe pane — so React Router matches both."
