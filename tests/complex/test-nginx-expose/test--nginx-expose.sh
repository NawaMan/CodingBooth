#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: nginx expose extension (end-to-end, template -> run-args -> host)
#
# test-boothfile-nginx already proves `setup nginx` puts the binary in the image.
# It does NOT prove the daemon actually serves, and it does not prove you can
# reach it. nginx auto-starts from its own /usr/share/startup.d/ hook but listens
# only on container port 80, so without a published port it is unreachable from
# the host. That is what `nginx/expose--extension` is for.
#
# This test walks the whole chain that extension is responsible for:
#
#   template  ->  run-args in config.toml  ->  docker -p  ->  curl from the HOST
#
# Every link matters, and the middle one is fragile in a way that fails SILENTLY:
# `run-args` is a top-level TOML key, so if it is ever written BELOW a
# [params.NGINX_PORT] table header, TOML scopes it into that table
# (params.NGINX_PORT.run-args), the loader finds no top-level run-args, and the
# port mapping vanishes. The template still compiles and `arg NGINX_PORT=...`
# still appears in the Boothfile, so the damage is invisible until someone
# notices the page won't load. Test 1 pins the mapping; test 4 proves it works.
#
# Note the ports here are deliberately odd (18080/18989) rather than the 8080
# default: a dev host is quite likely to have something on 8080 already, and a
# collision would fail this test for a reason that has nothing to do with nginx.
# The non-default port doubles as proof that `+expose:<port>` parameterizes.
#
# The .booth/ is GENERATED from the local templates rather than checked in as a
# fixture — a checked-in config.toml with a hand-written "-p" would still pass
# while the template that is supposed to produce it was broken.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../common--source.sh

echo "=== Test: nginx expose extension ==="

FAILED=0
NAME="test-nginx-expose-$$"
HTTP_PORT=18080      # host port -> container 80
BOOTH_PORT=18989     # the booth's own port, kept clear of the default 10000

TEMPLATES_PATH="$(cd ../../.. && pwd)/templates"

cleanup() {
  run_coding_booth remove --force --name "$NAME" >/dev/null 2>&1 || true
  rm -rf .booth
}
trap cleanup EXIT

rm -rf .booth

# --- Generate .booth/ from the LOCAL templates -------------------------------
# --templates-path is not optional here: without it, config would pull the
# RELEASED templates and this test would quietly stop testing the working tree.
run_coding_booth config . --no-tui --overwrite \
  --variant base \
  --templates-path "$TEMPLATES_PATH" \
  --select "nginx+expose:${HTTP_PORT}" >/dev/null 2>&1

# Test 1: the expose extension actually contributed the port mapping.
# This is the assertion that catches the TOML-scoping failure described above.
if grep -qF "\"${HTTP_PORT}:80\"" .booth/config.toml 2>/dev/null; then
  print_test_result "true" "$0" "1" "expose extension publishes host ${HTTP_PORT} -> container 80"
else
  print_test_result "false" "$0" "1" "expose extension should publish ${HTTP_PORT}:80 in run-args"
  echo "  .booth/config.toml:"
  sed 's/^/    /' .booth/config.toml 2>/dev/null || echo "    (missing)"
  FAILED=$((FAILED + 1))
fi

# --- Bring up a daemon booth --------------------------------------------------
run_coding_booth --silence-build --name "$NAME" --port "$BOOTH_PORT" --daemon --keep-alive \
  -- 'sleep 600' >/dev/null 2>&1

READY=false
for _ in $(seq 1 30); do
  if docker exec "$NAME" bash -lc 'true' >/dev/null 2>&1; then
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

# Test 2: nginx is installed in the image.
if docker exec "$NAME" bash -lc 'nginx -v' 2>&1 | grep -qiE 'nginx version'; then
  print_test_result "true" "$0" "2" "nginx is installed"
else
  print_test_result "false" "$0" "2" "nginx should be installed"
  FAILED=$((FAILED + 1))
fi

# Test 3: nginx auto-started on container boot and is serving on port 80 INSIDE
# the booth. This isolates the daemon from the port publishing — if this passes
# and test 4 fails, the bug is in the -p mapping, not in nginx.
SERVING_INSIDE=false
for _ in $(seq 1 30); do
  if docker exec "$NAME" bash -lc 'curl -sf -o /dev/null http://127.0.0.1:80/' >/dev/null 2>&1; then
    SERVING_INSIDE=true
    break
  fi
  sleep 1
done

if [[ "$SERVING_INSIDE" == true ]]; then
  print_test_result "true" "$0" "3" "nginx auto-started and serves on container port 80"
else
  print_test_result "false" "$0" "3" "nginx should auto-start and serve on container port 80"
  echo "  startup log:"
  docker exec "$NAME" bash -lc 'cat /tmp/startups.log 2>/dev/null | tail -20' 2>/dev/null | sed 's/^/    /' || true
  FAILED=$((FAILED + 1))
fi

# Test 4: the published port reaches nginx FROM THE HOST. This is the whole
# point of the extension, and the end of the chain the template started.
BODY=""
for _ in $(seq 1 30); do
  BODY=$(curl -sf "http://127.0.0.1:${HTTP_PORT}/" 2>/dev/null || true)
  if [[ -n "$BODY" ]]; then
    break
  fi
  sleep 1
done

if echo "$BODY" | grep -qi "welcome to nginx"; then
  print_test_result "true" "$0" "4" "nginx is reachable from the host on port ${HTTP_PORT}"
else
  print_test_result "false" "$0" "4" "nginx should be reachable from the host on port ${HTTP_PORT}"
  echo "  Actual body: ${BODY:-(empty)}"
  echo "  Published ports:"
  docker port "$NAME" 2>/dev/null | sed 's/^/    /' || echo "    (none)"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
