#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Native booth tools: copy outside code, inspect, stats, top, diff, wait, and
# copying a stopped kept booth. The fixture never copies through the code mount.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../../../common--source.sh

if [[ "$CB_ENGINE" != docker ]]; then
  echo "SKIP: this integration scenario verifies Docker's native output; other engines have Go routing tests."
  exit 0
fi
docker info >/dev/null
NAME="booth-tools-$RANDOM-$RANDOM"
while docker inspect "$NAME" >/dev/null 2>&1; do
  NAME="booth-tools-$RANDOM-$RANDOM"
done
PORT="$(pick_free_port)"
WORK="$(mktemp -d)"
WAITER=""
CREATED=false
cleanup() {
  if [[ "$CREATED" == true ]]; then
    docker rm -f "$NAME" >/dev/null 2>&1 || true
  fi
  if [[ -n "$WAITER" ]]; then wait "$WAITER" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

check() {
  local number="$1" description="$2"
  shift 2
  if "$@"; then
    print_test_result true "$0" "$number" "$description"
  else
    print_test_result false "$0" "$number" "$description"
    exit 1
  fi
}

mkdir -p "$WORK/code" "$WORK/source/nested" "$WORK/download"
printf 'first\n' > "$WORK/source/file with spaces.txt"
printf 'nested\n' > "$WORK/source/nested/data"
CREATED=true
run_coding_booth --engine docker --variant base --name "$NAME" --code "$WORK/code" \
  --port "$PORT" --daemon --keep-alive --no-browser > "$0.log" 2>&1
for attempt in {1..60}; do
  if docker exec "$NAME" id coder >/dev/null 2>&1; then break; fi
  sleep 1
done
check 1 "The booth has a coder user" docker exec "$NAME" id coder

run_coding_booth cp --engine docker "$WORK/source/file with spaces.txt" "$NAME:/tmp/booth-tools-file"
run_coding_booth cp --engine docker "$NAME:/tmp/booth-tools-file" "$WORK/returned.txt"
check 2 "A file outside the code mount round-trips unchanged" cmp "$WORK/source/file with spaces.txt" "$WORK/returned.txt"

printf 'replacement\n' > "$WORK/source/file with spaces.txt"
run_coding_booth cp --name "$NAME" --engine docker "$WORK/source/file with spaces.txt" :/tmp/booth-tools-file
run_coding_booth cp --code "$WORK/code" --engine docker :/tmp/booth-tools-file "$WORK/returned.txt"
check 3 "Copy overwrites an existing file and --code selects the booth" cmp "$WORK/source/file with spaces.txt" "$WORK/returned.txt"

run_coding_booth cp --engine docker "$WORK/source" "$NAME:/tmp/booth-tools-dir"
run_coding_booth cp --engine docker "$NAME:/tmp/booth-tools-dir/." "$WORK/download/"
check 4 "Directory contents copy recursively without extra nesting" cmp "$WORK/source/nested/data" "$WORK/download/nested/data"

run_coding_booth cp --engine docker "$NAME:/tmp/booth-tools-file" - > "$WORK/result.tar"
tar -xf "$WORK/result.tar" -C "$WORK/download"
check 5 "Tar stdout is unpolluted" cmp "$WORK/returned.txt" "$WORK/download/booth-tools-file"
# --no-xattrs because macOS 15 stamps every file with com.apple.provenance and
# BSD tar stores xattrs by default, which the daemon then refuses to apply in a
# Linux container: `lsetxattr /tmp/nested: xattr "com.apple.provenance":
# operation not supported`, and the copy never happens. --no-mac-metadata, the
# flag that sounds right, does not drop it. GNU tar takes the same flag.
tar --no-xattrs -cf "$WORK/input.tar" -C "$WORK/source" nested
run_coding_booth cp --engine docker - "$NAME:/tmp/" < "$WORK/input.tar"
run_coding_booth cp --engine docker "$NAME:/tmp/nested/data" "$WORK/from-tar"
check 6 "Tar stdin extracts into the booth" cmp "$WORK/source/nested/data" "$WORK/from-tar"

run_coding_booth inspect "$NAME" --engine docker --json > "$WORK/inspect.json"
check 7 "Inspect retains native mounts and container identity" jq -e --arg name "/$NAME" '.[0].Name == $name and (.[0].Mounts | length > 0)' "$WORK/inspect.json"
run_coding_booth list --engine docker --json > "$WORK/list.json"
check 8 "List JSON identifies the owning engine" jq -e --arg name "$NAME" 'any(.[]; .name == $name and .engine == "docker")' "$WORK/list.json"
run_coding_booth expose list "$NAME" --engine docker --json > "$WORK/ports.json"
check 9 "Expose JSON includes the live published port" jq -e --argjson port "$PORT" 'any(.ports[]; .host_port == $port and .live)' "$WORK/ports.json"
run_coding_booth stats "$NAME" --engine docker --no-stream --format '{{.Name}}' > "$WORK/stats"
check 10 "One-shot statistics target this booth" grep -Fx "$NAME" "$WORK/stats"
run_coding_booth top "$NAME" --engine docker > "$WORK/top"
check 11 "Top reports processes" test -s "$WORK/top"
run_coding_booth diff "$NAME" --engine docker > "$WORK/diff"
check 12 "Diff reports the copied file outside code" grep -F '/tmp/booth-tools-file' "$WORK/diff"

if run_coding_booth cp --engine docker "$NAME:/tmp/does-not-exist-booth-tools" "$WORK/missing" > "$WORK/error" 2>&1; then
  print_test_result false "$0" 13 "Copy of a missing source must fail"
  exit 1
fi
check 13 "Native copy failure explains the missing source" grep -F 'does-not-exist-booth-tools' "$WORK/error"

run_coding_booth wait "$NAME" --engine docker > "$WORK/wait" 2> "$WORK/wait.err" &
WAITER=$!
run_coding_booth stop "$NAME" --engine docker --timeout 1
wait "$WAITER"
WAITER=""
EXPECTED_EXIT="$(docker inspect -f '{{.State.ExitCode}}' "$NAME")"
check 14 "Wait prints the stopped booth's exit code" grep -Fx "$EXPECTED_EXIT" "$WORK/wait"

run_coding_booth cp --engine docker "$WORK/source/nested/data" "$NAME:/tmp/copied-while-stopped"
run_coding_booth cp --engine docker "$NAME:/tmp/copied-while-stopped" "$WORK/stopped-copy"
check 15 "Stopped booths can receive and return files" cmp "$WORK/source/nested/data" "$WORK/stopped-copy"
check 16 "Copy and wait leave the booth stopped" test "$(docker inspect -f '{{.State.Running}}' "$NAME")" = false
run_coding_booth remove "$NAME" --engine docker
CREATED=false
