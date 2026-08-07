#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Build if needed, then serve Tripboard. Run this inside the booth.
#
#   ./start.sh              # http://localhost:8090/
#   PORT=9000 ./start.sh    # if 8090 is taken (map the new port in config.toml)
#
# On the very first run this also creates pb_data/ and applies the migrations,
# so the demo trip is on screen before you have typed anything else.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PORT="${PORT:-8090}"

# `go build` is incremental, so building on every start costs next to nothing
# and removes the "why is my edit not showing up" question entirely.
"$ROOT_DIR/build.sh"

echo ""
echo "Serving on http://localhost:${PORT}/     (admin UI: /_/)"
echo "Editing needs an account — if you have not made one yet, stop this and run:"
echo "  ./tripboard superuser upsert you@example.com 'a-strong-password'"
echo ""

# 0.0.0.0, not localhost: the booth publishes this port to the host, and a
# server listening on the loopback would ignore that mapping.
exec ./tripboard serve --http="0.0.0.0:${PORT}"
