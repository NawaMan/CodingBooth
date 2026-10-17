#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: two DinD booths from folders with the same name
#
# Booth A runs with its default name (the folder name). Booth B starts from a
# second folder of the same name — a worktree copy of an example is the usual
# way this happens. Each publishes its front door plus one -p port through its
# DinD sidecar.
#
# 1) A's .booth/.tmp/ports.json lists its front door and its -p port. They were
#    once written after SetupDind had moved the -p flags onto the sidecar, and
#    the front door was left out, so the file said "published": null.
# 2) Host `expose list` shows both of A's ports as live, read from the sidecar
#    (the booth itself shares the sidecar's network and binds nothing).
# 3) Starting B leaves A's sidecar running. Start-up cleanup once matched
#    leftover sidecars by project name, so B removed A's and cut A off.
# 4) A's front door still answers after B started.
# 5) B's own manifest lists B's ports, not A's.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

FAILED=0
TWIN="dindtwin-$$"          # the shared folder (project) name
NAME_A="$TWIN"              # A keeps the default name, which is what B's cleanup used to match
NAME_B="$TWIN-b"
PORT_A="$(pick_free_port)"
PORT_B="$(pick_free_port_other_than "$PORT_A")"
APP_A="$(pick_free_port_other_than "$PORT_A" "$PORT_B")"
APP_B="$(pick_free_port_other_than "$PORT_A" "$PORT_B" "$APP_A")"

WORK="$(mktemp -d)"
DIR_A="$WORK/a/$TWIN"
DIR_B="$WORK/b/$TWIN"

cleanup() {
  local name
  for name in "$NAME_A" "$NAME_B"; do
    run_coding_booth stop --name "$name" >/dev/null 2>&1 || true
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker ps -aq --filter "label=cb.parent=$name" | xargs -r docker rm -f >/dev/null 2>&1 || true
  done
  docker network ls --format '{{.Name}}' | grep "^$TWIN-" | xargs -r docker network rm >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Same folder name, same config shape, different ports.
for side in A B; do
  dir_var="DIR_$side"; app_var="APP_$side"
  mkdir -p "${!dir_var}/.booth"
  printf 'dind = true\n\nrun-args = [\n    "-p", "%s:8080"\n]\n' "${!app_var}" > "${!dir_var}/.booth/config.toml"
done

sidecar_of() { docker ps -q --filter "label=cb.role=sidecar" --filter "label=cb.parent=$1"; }

# manifest_has <dir> <container_port> <host_port>
manifest_has() {
  grep -A3 "\"host_port\": $3," "$1/.booth/.tmp/ports.json" 2>/dev/null | grep -q "\"container_port\": $2,"
}

# ---- Start A -----------------------------------------------------------------
booth_step 0 "start booth A (DinD, daemon)" \
  --code "$DIR_A" --daemon --dind --dind-allowed --no-browser --port "$PORT_A" \
  || exit 1

# Test 1: A's manifest lists the front door and the -p port.
if manifest_has "$DIR_A" 10000 "$PORT_A" && manifest_has "$DIR_A" 8080 "$APP_A"; then
  print_test_result "true" "$0" "1" "DinD booth's ports.json lists front door and -p port"
else
  print_test_result "false" "$0" "1" "DinD booth's ports.json should list front door and -p port"
  command cat "$DIR_A/.booth/.tmp/ports.json" 2>/dev/null | sed 's/^/  /' || echo "  (no ports.json)"
  FAILED=$((FAILED + 1))
fi

# Test 2: host expose list sees both as live, through the sidecar.
LIST="$(run_coding_booth expose list --name "$NAME_A" 2>&1)" || true
if echo "$LIST" | grep -E "^10000 +127\.0\.0\.1:$PORT_A .* yes " >/dev/null \
   && echo "$LIST" | grep -E "^8080 +[0-9.]+:$APP_A .* yes " >/dev/null; then
  print_test_result "true" "$0" "2" "host expose list shows the DinD booth's ports as live"
else
  print_test_result "false" "$0" "2" "host expose list should show the DinD booth's ports as live"
  echo "$LIST" | sed 's/^/  /'
  FAILED=$((FAILED + 1))
fi

SIDECAR_A="$(sidecar_of "$NAME_A")"

# ---- Start B from the twin folder ---------------------------------------------
booth_step 0 "start booth B (DinD, daemon) from a same-named folder" \
  --code "$DIR_B" --daemon --dind --dind-allowed --no-browser --port "$PORT_B" --name "$NAME_B" \
  || FAILED=$((FAILED + 1))

# Test 3: A's sidecar is still the same running container.
if [[ -n "$SIDECAR_A" && "$(sidecar_of "$NAME_A")" == "$SIDECAR_A" ]]; then
  print_test_result "true" "$0" "3" "starting B leaves A's sidecar running"
else
  print_test_result "false" "$0" "3" "starting B should leave A's sidecar running"
  docker ps -a --filter "label=cb.role=sidecar" --format '  {{.Names}} {{.Status}} {{.Label "cb.parent"}}' | grep "$TWIN" || true
  FAILED=$((FAILED + 1))
fi

# Test 4: A's front door still answers.
CODE="$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://127.0.0.1:$PORT_A/" || true)"
if [[ "$CODE" =~ ^[23] ]]; then
  print_test_result "true" "$0" "4" "A's front door answers after B started"
else
  print_test_result "false" "$0" "4" "A's front door should answer after B started (got $CODE)"
  FAILED=$((FAILED + 1))
fi

# Test 5: B's manifest has B's ports.
if manifest_has "$DIR_B" 10000 "$PORT_B" && manifest_has "$DIR_B" 8080 "$APP_B"; then
  print_test_result "true" "$0" "5" "second booth's ports.json lists its own ports"
else
  print_test_result "false" "$0" "5" "second booth's ports.json should list its own ports"
  command cat "$DIR_B/.booth/.tmp/ports.json" 2>/dev/null | sed 's/^/  /' || echo "  (no ports.json)"
  FAILED=$((FAILED + 1))
fi

exit "$FAILED"
