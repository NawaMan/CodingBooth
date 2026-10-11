#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Test: two booths of the same folder get separate {name} volumes.
#
# .booth/config.toml mounts booth-voltest-{name}, the way the service templates
# mount booth-pgdata-{name}. {name} is the booth's final name, so the first booth
# (named after the folder) and a second concurrent one (auto-named
# <project>-<port>) must not share a data folder.
#
# Test 1: the first booth mounts booth-voltest-<project>, labelled with its booth.
# Test 2: a second concurrent booth mounts booth-voltest-<project>-<port>.
# Test 3: the second booth starts empty: it does not see the first booth's data.
# Test 4: its first start printed the notice with the copy command.
# Test 5: writing in the second booth leaves the first booth's data alone.
# Test 6: data follows the name — the second booth, removed and started again
#         by its name, finds its own data, with no notice this time.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../../common--source.sh

FAILED=0
PROJECT="test-booth-volumes" # = sanitized basename of this directory
FIRST_VOLUME="booth-voltest-$PROJECT"
SECOND=""
STDERR_FILE="$(mktemp)"

cleanup() {
  # Every booth and volume this test could have created for this project.
  docker ps -aq --filter "label=cb.project=$PROJECT" 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker volume ls -q --filter "label=cb.project=$PROJECT" 2>/dev/null | xargs -r docker volume rm >/dev/null 2>&1 || true
  rm -f "$STDERR_FILE"
}
trap cleanup EXIT
cleanup # start clean in case a previous run left containers or volumes behind
STDERR_FILE="$(mktemp)"

host_port_10000() {
  docker inspect -f '{{(index (index .HostConfig.PortBindings "10000/tcp") 0).HostPort}}' "$1" 2>/dev/null || true
}
volume_label() { docker volume inspect -f "{{index .Labels \"$2\"}}" "$1" 2>/dev/null || true; }
mounted_volume() { # booth, container path -> the volume name mounted there
  docker inspect -f "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Name}}{{end}}{{end}}" "$1" 2>/dev/null || true
}
read_data() { docker exec --user coder "$1" cat /home/coder/.voltest/who 2>/dev/null || true; }
write_data() { docker exec --user coder "$1" bash -c "echo $2 > /home/coder/.voltest/who"; }

# Test 1: the first booth is named after the folder and mounts booth-voltest-<project>.
run_coding_booth --variant base --daemon --keep-alive -- 'sleep 300' >/dev/null 2>&1 || true
if [[ "$(mounted_volume "$PROJECT" /home/coder/.voltest)" == "$FIRST_VOLUME" ]] \
   && [[ "$(volume_label "$FIRST_VOLUME" cb.booth)" == "$PROJECT" ]] \
   && [[ "$(volume_label "$FIRST_VOLUME" cb.project)" == "$PROJECT" ]]; then
  print_test_result "true" "$0" "1" "first booth mounts $FIRST_VOLUME, labelled cb.booth=$PROJECT"
else
  print_test_result "false" "$0" "1" "first booth should mount $FIRST_VOLUME (got '$(mounted_volume "$PROJECT" /home/coder/.voltest)')"
  exit 1
fi
write_data "$PROJECT" first

# Test 2: a second concurrent booth gets <project>-<port> and its own volume.
run_coding_booth --variant base --daemon --keep-alive -- 'sleep 300' >/dev/null 2>"$STDERR_FILE" || true
SECOND="$(docker ps -a --filter "label=cb.project=$PROJECT" --format '{{.Names}}' 2>/dev/null | grep -v "^${PROJECT}\$" | head -1 || true)"
SECOND_VOLUME="booth-voltest-$SECOND"
if [[ -n "$SECOND" ]] && [[ "$SECOND" == "${PROJECT}-$(host_port_10000 "$SECOND")" ]] \
   && [[ "$(mounted_volume "$SECOND" /home/coder/.voltest)" == "$SECOND_VOLUME" ]] \
   && [[ "$(volume_label "$SECOND_VOLUME" cb.booth)" == "$SECOND" ]] \
   && [[ "$(volume_label "$SECOND_VOLUME" cb.project)" == "$PROJECT" ]]; then
  print_test_result "true" "$0" "2" "second booth '$SECOND' mounts its own $SECOND_VOLUME"
else
  print_test_result "false" "$0" "2" "second booth should mount booth-voltest-<project>-<port> (booth '${SECOND:-<none>}', volume '$(mounted_volume "${SECOND:-none}" /home/coder/.voltest)')"
  cat "$STDERR_FILE"
  exit 1
fi

# Test 3: the second booth starts empty.
if [[ -z "$(read_data "$SECOND")" ]]; then
  print_test_result "true" "$0" "3" "second booth does not see the first booth's data"
else
  print_test_result "false" "$0" "3" "second booth should start empty, read '$(read_data "$SECOND")'"
  FAILED=$((FAILED + 1))
fi

# Test 4: the notice points at the first booth's data, with the copy command.
if grep -qF -- "-v $FIRST_VOLUME:/from -v $SECOND_VOLUME:/to" "$STDERR_FILE"; then
  print_test_result "true" "$0" "4" "second booth's first start printed the copy notice"
else
  print_test_result "false" "$0" "4" "second booth's first start should print the copy notice"
  cat "$STDERR_FILE"
  FAILED=$((FAILED + 1))
fi

# Test 5: writing in the second booth leaves the first booth's data alone.
write_data "$SECOND" second
if [[ "$(read_data "$PROJECT")" == "first" ]] && [[ "$(read_data "$SECOND")" == "second" ]]; then
  print_test_result "true" "$0" "5" "each booth keeps its own data"
else
  print_test_result "false" "$0" "5" "data crossed: first='$(read_data "$PROJECT")' second='$(read_data "$SECOND")'"
  FAILED=$((FAILED + 1))
fi

# Test 6: data follows the name — recreate the second booth by name.
docker rm -f "$SECOND" >/dev/null 2>&1 || true
run_coding_booth --variant base --daemon --keep-alive --name "$SECOND" -- 'sleep 300' >/dev/null 2>"$STDERR_FILE" || true
if [[ "$(read_data "$SECOND")" == "second" ]] && ! grep -qF "Notice:" "$STDERR_FILE"; then
  print_test_result "true" "$0" "6" "booth '$SECOND' started again by name finds its own data, no notice"
else
  print_test_result "false" "$0" "6" "booth '$SECOND' started again should read 'second' quietly, read '$(read_data "$SECOND")'"
  cat "$STDERR_FILE"
  FAILED=$((FAILED + 1))
fi

exit $FAILED
