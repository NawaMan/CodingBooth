#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select postgresql+pg-ext-pkg:pgvector,pg_trgm/postgrest+autostart+expose:+3000

# Auto-start PostgREST after PostgreSQL (LEVEL 50).
PORT=${POSTGREST_PORT:-3000}
LOG_FILE="/tmp/postgrest.log"

if command -v pg_isready >/dev/null 2>&1; then
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    pg_isready -q && break
    sleep 1
  done
fi

export PGRST_DB_URI="${PGRST_DB_URI:-postgres:///postgres}"
export PGRST_DB_SCHEMAS="${PGRST_DB_SCHEMAS:-public}"
export PGRST_DB_ANON_ROLE="${PGRST_DB_ANON_ROLE:-${USER:-coder}}"
export PGRST_SERVER_PORT="$PORT"
export PGRST_SERVER_HOST="${PGRST_SERVER_HOST:-0.0.0.0}"

nohup postgrest > "$LOG_FILE" 2>&1 &

echo "PostgREST started on port $PORT (PID $!, log: $LOG_FILE)"
