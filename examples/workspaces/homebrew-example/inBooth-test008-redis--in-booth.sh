#!/bin/bash
# Test: Redis

echo "=== Testing Redis ==="

# Use a random port to avoid conflicts
PORT=$((6380 + $$))

cleanup() {
    redis-cli -p "$PORT" shutdown nosave 2>/dev/null || true
}
trap cleanup EXIT

redis-server --port "$PORT" --daemonize yes
sleep 1
redis-cli -p "$PORT" ping
redis-cli -p "$PORT" set test "Redis works!" > /dev/null
redis-cli -p "$PORT" get test
