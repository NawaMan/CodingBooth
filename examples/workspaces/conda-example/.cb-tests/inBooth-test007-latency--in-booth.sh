#!/bin/bash
echo "=== Testing API latency report ==="
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(just run)"
echo "$OUT"
echo "$OUT" | grep -q "^595 requests"
echo "$OUT" | grep -qE "^GET /health +63 "
echo "$OUT" | grep -q "Slowest p95: GET /api/search"
just run /api/orders | grep -q "Slowest p95: POST /api/orders"
if just run /no-such-endpoint >/dev/null 2>&1; then
    echo "an unknown endpoint should fail"
    exit 1
fi
