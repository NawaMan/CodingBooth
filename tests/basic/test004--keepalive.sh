#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

function generate_name() {
  local name
  while :; do
    name=$(printf "name-%04d" $((RANDOM % 10000)))
    if ! docker inspect "$name" >/dev/null 2>&1; then
      break
    fi
  done
  echo "$name"
}

RunWorkspace() {
  local name="$1"
  local port="$2"
  run_coding_booth --variant base --name "$name" --port "$port" --daemon --keep-alive -- sleep 10
}

NAME="$(generate_name)"
PORT="$(pick_free_port)"

RunWorkspace "$NAME" "$PORT" > $0.log 2>/dev/null

# --- Wait for container to appear (max ~10 seconds) ---
for i in {1..10}; do
  if docker inspect "$NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
# -------------------------------------------------------

if docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "true" "$0" "1" "Container '$NAME' exists and exposes expected port $PORT"
else
  print_test_result "false" "$0" "1" "Container '$NAME' exists and exposes expected port $PORT"
  exit 1
fi


# --- Wait for container to appear (max ~60 seconds) ---
for i in {1..60}; do
  if docker inspect "$NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
# -------------------------------------------------------

if docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "true" "$0" "2" "Container '$NAME' still exists as it is kept alive"
else
  print_test_result "false" "$0" "2" "Container '$NAME' does NOT exist -- it was not kept alive"
  exit 1
fi

docker stop $NAME >/dev/null 2>&1 || true
docker rm   $NAME >/dev/null 2>&1 || true

if ! docker inspect "$NAME" >/dev/null 2>&1; then
  print_test_result "true" "$0" "3" "Container '$NAME' has now been removed"
else
  print_test_result "false" "$0" "3" "Container '$NAME' still exists even after explicit removal request"
  exit 1
fi
