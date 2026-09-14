#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: PostgreSQL extensions (pg-ext-pkg) and PostgREST, end to end
#
# tests/setups, tests/boothfile and tests/config already prove the install
# script's package resolution, the Boothfile/Dockerfile compilation, and the
# template-selection wiring in isolation, all without building an image. None
# of that proves the extensions are actually enabled in a running database, or
# that PostgREST is actually serving — CREATE EXTENSION and postgrest's
# autostart both happen in a container-boot startup hook, which only a real
# `docker run` exercises. This test builds the real image and checks a live
# container.
#
# Grouped as one test rather than two: pg-ext-pkg has no meaning without
# postgresql, and this postgrest selection needs postgresql too (`requires`),
# so a single booth with both selected covers the whole feature pair for the
# cost of one image build instead of two.
#
# The .booth/ is GENERATED from the local templates rather than checked in as
# a fixture, for the same reason test-nginx-expose does this: a checked-in
# config.toml would still pass while the template that is supposed to produce
# it was broken.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: PostgreSQL extensions + PostgREST ==="

FAILED=0
NAME="test-boothfile-postgres-addons-$$"
POSTGREST_HTTP_PORT=18300   # host port -> container 3000
BOOTH_PORT=18991             # the booth's own port, kept clear of other complex tests

TEMPLATES_PATH="$(cd ../../.. && pwd)/templates"

cleanup() {
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
  rm -rf .booth
}
trap cleanup EXIT

rm -rf .booth

# --- Generate .booth/ from the LOCAL templates -------------------------------
run_coding_booth config . --no-tui --overwrite \
  --variant base \
  --templates-path "$TEMPLATES_PATH" \
  --select "postgresql+pg-ext-pkg:pgvector,pg_trgm,postgis" \
  --select "postgrest+autostart+expose:${POSTGREST_HTTP_PORT}" >/dev/null 2>&1

# Test 1: the expose extension actually contributed the port mapping. Catches
# the same class of bug test-nginx-expose's test 1 guards against: run-args
# written below a [params.X] table header silently scopes into that table
# instead of landing at the top level, and the port mapping vanishes.
if grep -qF "\"${POSTGREST_HTTP_PORT}:3000\"" .booth/config.toml 2>/dev/null; then
  print_test_result "true" "$0" "1" "expose extension publishes host ${POSTGREST_HTTP_PORT} -> container 3000"
else
  print_test_result "false" "$0" "1" "expose extension should publish ${POSTGREST_HTTP_PORT}:3000 in run-args"
  echo "  .booth/config.toml:"
  sed 's/^/    /' .booth/config.toml 2>/dev/null || echo "    (missing)"
  FAILED=$((FAILED + 1))
fi

# --- Bring up a daemon booth --------------------------------------------------
run_coding_booth --silence-build --name "$NAME" --port "$BOOTH_PORT" --daemon --keep-alive \
  -- 'sleep 600' >/dev/null 2>&1

READY=false
for _ in $(seq 1 30); do
  if docker exec -u coder "$NAME" bash -lc 'true' >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 1
done

if [[ "$READY" != true ]]; then
  print_test_result "false" "$0" "2" "Daemon booth failed to start"
  FAILED=$((FAILED + 1))
  exit $FAILED
fi

# Test 2: the requested extensions are actually enabled in the database, not
# merely apt-installed. pgvector is the interesting one — its package name
# does not match its CREATE EXTENSION name (control file is vector.control),
# so this is the check that would have caught pg-ext--install.sh silently
# recording the wrong identifier in the manifest.
EXTENSIONS=""
for _ in $(seq 1 30); do
  EXTENSIONS=$(docker exec -u coder "$NAME" bash -lc \
    'psql -d postgres -tAc "SELECT extname FROM pg_extension ORDER BY extname"' 2>/dev/null || true)
  if [[ -n "$EXTENSIONS" ]]; then
    break
  fi
  sleep 1
done

for ext in pg_trgm postgis vector; do
  if echo "$EXTENSIONS" | grep -qx "$ext"; then
    print_test_result "true" "$0" "2-${ext}" "extension '${ext}' is enabled (CREATE EXTENSION ran)"
  else
    print_test_result "false" "$0" "2-${ext}" "extension '${ext}' should be enabled"
    echo "  actual pg_extension rows: ${EXTENSIONS:-(empty)}"
    FAILED=$((FAILED + 1))
  fi
done

# Test 3: PostgREST auto-started and is serving on container port 3000 INSIDE
# the booth. Isolates the daemon from the port publishing — if this passes and
# test 4 fails, the bug is in the -p mapping, not in PostgREST or its startup.
SERVING_INSIDE=false
for _ in $(seq 1 30); do
  if docker exec -u coder "$NAME" bash -lc 'curl -sf -o /dev/null http://127.0.0.1:3000/' >/dev/null 2>&1; then
    SERVING_INSIDE=true
    break
  fi
  sleep 1
done

if [[ "$SERVING_INSIDE" == true ]]; then
  print_test_result "true" "$0" "3" "PostgREST auto-started and serves on container port 3000"
else
  print_test_result "false" "$0" "3" "PostgREST should auto-start and serve on container port 3000"
  echo "  postgrest log:"
  docker exec -u coder "$NAME" bash -lc 'cat /tmp/postgrest.log 2>/dev/null | tail -20' 2>/dev/null | sed 's/^/    /' || true
  FAILED=$((FAILED + 1))
fi

# Test 4: the published port reaches PostgREST FROM THE HOST.
BODY_CODE=""
for _ in $(seq 1 30); do
  BODY_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${POSTGREST_HTTP_PORT}/" 2>/dev/null || true)
  if [[ "$BODY_CODE" == "200" ]]; then
    break
  fi
  sleep 1
done

if [[ "$BODY_CODE" == "200" ]]; then
  print_test_result "true" "$0" "4" "PostgREST is reachable from the host on port ${POSTGREST_HTTP_PORT}"
else
  print_test_result "false" "$0" "4" "PostgREST should be reachable from the host on port ${POSTGREST_HTTP_PORT}"
  echo "  Actual HTTP status: ${BODY_CODE:-(none)}"
  echo "  Published ports:"
  docker port "$NAME" 2>/dev/null | sed 's/^/    /' || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
