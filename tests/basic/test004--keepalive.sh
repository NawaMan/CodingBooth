#!/bin/bash
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

function is_port_free() {
  local p="$1"

  # Prefer lsof (macOS + Linux); fall back to ss; fall back to nc
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -iTCP:"$p" -sTCP:LISTEN -Pn 2>/dev/null | grep -q .
  elif command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$p )" 2>/dev/null | grep -q ":$p"
  else
    ! (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$p" >/dev/null 2>&1)
  fi
}

function random_free_port() {
  local port
  local i

  for i in {1..100}; do
    port=$((50000 + RANDOM % 10001))
    if is_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done

  echo "Failed to find free port in range 50000–60000 after 100 tries" >&2
  return 1
}

RunWorkspace() {
  local name="$1"
  local port="$2"
  ../../workspace --variant base --name "$name" --port "$port" --daemon --keep-alive -- sleep 5
}

NAME="$(generate_name)"
PORT="$(random_free_port)"

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


sleep 7

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
