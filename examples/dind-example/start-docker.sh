#!/usr/bin/env bash
set -euo pipefail


SERVER_PORT=${SERVER_PORT:-8080}

SOCAT_PID="$(/usr/local/bin/dind-open-port "$SERVER_PORT")"
cleanup() { /usr/local/bin/dind-open-port "$SOCAT_PID" ; }
trap cleanup EXIT INT TERM


DOCKER_BUILDKIT=1 docker build -t http-server .

echo
echo "Start http-server on port ${SERVER_PORT} ... "
echo "Press Ctrl+C to terminate."
docker run -p ${SERVER_PORT}:${SERVER_PORT} http-server
