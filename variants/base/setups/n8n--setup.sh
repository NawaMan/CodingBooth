#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--port <port>]

Examples:
  $0                                  # n8n 2.41.5 on port 21200
  $0 --version 2.41.5 --port 5678     # pin both

Notes:
- Installs n8n with npm into the catalog Node.js (engines: >= 24)
- SQLite data directory is ~/.n8n (select +persist to keep it)
- Builds the Python task runner from the matching n8n tag, so Code nodes run
  Python as well as JavaScript in internal mode (no Docker needed)
- Does not start the server. Select +autostart, and +expose to publish the port.
- Installs start-n8n-sandbox / stop-n8n-sandbox for the Assistant's code
  sandbox (n8n's sandbox service on Docker). Select +sandbox, which needs dind.
- Installs start-n8n-search / stop-n8n-search for the Assistant's web search
  (SearXNG on Docker). Select +search, which needs dind. A Brave Search key in
  INSTANCE_AI_BRAVE_SEARCH_API_KEY needs no service and takes priority.
- n8n 2.x is the npm line. A later major may ship as a container image only;
  pin a 2.x version when "latest" stops installing.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

# ---- defaults / args ----
N8N_FALLBACK_VER="2.41.5"
N8N_PORT="21200"
REQ_VER="$N8N_FALLBACK_VER"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-$N8N_FALLBACK_VER}"; shift ;;
    --port) shift; N8N_PORT="${1:-21200}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        N8N_PORT="$1"; shift
      else
        echo "❌ Unknown arg: $1" >&2; usage; exit 2
      fi
      ;;
  esac
done

if [[ "$REQ_VER" != "latest" && ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not an n8n version: '${REQ_VER}' (expected X.Y.Z or latest)" >&2
  exit 2
fi
if [[ ! "$N8N_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ Not a port: '${N8N_PORT}'" >&2
  exit 2
fi

node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  command -v npm >/dev/null 2>&1 || return 1
  local major
  major="$(node -v | sed 's/^v//' | cut -d. -f1)"
  [[ "${major:-0}" -ge 24 ]] || return 1
}

if ! node_ok; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  NODE_SETUP=""
  for candidate in "$SCRIPT_DIR/nodejs--setup.sh" /opt/codingbooth/setups/nodejs--setup.sh; do
    if [[ -x "$candidate" ]]; then
      NODE_SETUP="$candidate"
      break
    fi
  done
  if [[ -z "$NODE_SETUP" ]]; then
    echo "❌ n8n needs Node.js >= 24 and nodejs--setup.sh was not found" >&2
    exit 1
  fi
  echo "• Installing Node.js 24 (n8n 2.x engines require >= 24) ..."
  "$NODE_SETUP" 24
fi
node_ok || { echo "❌ Node.js >= 24 is still not on PATH ($(node -v 2>/dev/null || echo missing))" >&2; exit 1; }

# node-gyp fallback when a native module has no prebuild for this Node.
export DEBIAN_FRONTEND=noninteractive
if ! command -v python3 >/dev/null 2>&1 || ! command -v g++ >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends python3 make g++
  rm -rf /var/lib/apt/lists/*
fi

echo "⬇️  Installing n8n@${REQ_VER} with npm (Node $(node -v)) ..."
if [[ "$REQ_VER" == "latest" ]]; then
  NPM_SPEC="n8n"
else
  NPM_SPEC="n8n@${REQ_VER}"
fi
npm install -g --unsafe-perm --no-fund --no-audit --cache /tmp/npm-cache "$NPM_SPEC"
rm -rf /tmp/npm-cache /root/.npm
command -v n8n >/dev/null 2>&1 || { echo "❌ n8n was installed but the binary is not on PATH" >&2; exit 1; }
N8N_INSTALLED_VER="$(n8n --version 2>/dev/null | tail -1)"
[[ "$N8N_INSTALLED_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ Cannot read the installed n8n version: '${N8N_INSTALLED_VER}'" >&2; exit 1; }

# ---- Python task runner (internal mode, no Docker) ----
# The Code node runs Python in n8n's task runner. n8n launches it as
# <node_modules>/@n8n/task-runner-python/.venv/bin/python -m src.main, but the
# npm package does not ship that directory: upstream only builds it into the
# n8nio/runners image, and it is not on PyPI. Build it here from the same tag,
# with the locked dependencies, on the system python3 (needs >= 3.13).
PY_RUNNER_DIR="$(npm root -g)/@n8n/task-runner-python"
echo "⬇️  Building the n8n Python task runner (n8n@${N8N_INSTALLED_VER}) ..."
if ! command -v uv >/dev/null 2>&1; then
  # Same install python--setup.sh uses, so a booth with the python template reuses it.
  UV_INSTALLER="$(mktemp)"
  curl -LsSf --retry 5 --retry-delay 3 --retry-all-errors -o "$UV_INSTALLER" https://astral.sh/uv/install.sh
  env UV_UNMANAGED_INSTALL="/usr/local/uv" sh "$UV_INSTALLER"
  rm -f "$UV_INSTALLER"
  if [ -x /usr/local/uv/uv ]; then
    export PATH="/usr/local/uv:$PATH"
  elif [ -x /usr/local/uv/bin/uv ]; then
    export PATH="/usr/local/uv/bin:$PATH"
  fi
  hash -r 2>/dev/null || true
fi
command -v uv >/dev/null 2>&1 || { echo "❌ uv not on PATH" >&2; exit 1; }
chmod -R a+rX /usr/local/uv 2>/dev/null || true

PY_RUNNER_TMP="$(mktemp -d)"
git -c advice.detachedHead=false clone --quiet --depth 1 --filter=blob:none --sparse \
  --branch "n8n@${N8N_INSTALLED_VER}" https://github.com/n8n-io/n8n.git "$PY_RUNNER_TMP/n8n"
git -C "$PY_RUNNER_TMP/n8n" sparse-checkout set packages/@n8n/task-runner-python
rm -rf "$PY_RUNNER_DIR"
mkdir -p "$(dirname "$PY_RUNNER_DIR")"
cp -a "$PY_RUNNER_TMP/n8n/packages/@n8n/task-runner-python" "$PY_RUNNER_DIR"
rm -rf "$PY_RUNNER_DIR/tests"
# The venv links to /usr/bin/python3 itself, so a catalog Python selected later
# does not move it. UV_PYTHON overrides the package's .python-version (3.13).
(cd "$PY_RUNNER_DIR" && \
  UV_PYTHON=/usr/bin/python3 UV_PYTHON_DOWNLOADS=never UV_CACHE_DIR="$PY_RUNNER_TMP/uv-cache" \
  uv sync --frozen --no-dev --no-install-project)
rm -rf "$PY_RUNNER_TMP"
chmod -R a+rX "$PY_RUNNER_DIR"
"$PY_RUNNER_DIR/.venv/bin/python" -c 'import websockets, urllib3' \
  || { echo "❌ The Python task runner venv does not import its dependencies" >&2; exit 1; }

STARTER_FILE="/usr/local/bin/start-n8n"
STOPPER_FILE="/usr/local/bin/stop-n8n"
PROFILE_FILE="/etc/profile.d/70-cb-n8n--profile.sh"
SANDBOX_STARTER_FILE="/usr/local/bin/start-n8n-sandbox"
SANDBOX_STOPPER_FILE="/usr/local/bin/stop-n8n-sandbox"
SEARCH_STARTER_FILE="/usr/local/bin/start-n8n-search"
SEARCH_STOPPER_FILE="/usr/local/bin/stop-n8n-search"

cat > "${STARTER_FILE}" <<STARTER
#!/usr/bin/env bash
set -euo pipefail

PORT="\${1:-\${N8N_PORT:-${N8N_PORT}}}"
export N8N_PORT="\$PORT"
export N8N_LISTEN_ADDRESS="\${N8N_LISTEN_ADDRESS:-0.0.0.0}"
# n8n keeps its data in \$N8N_USER_FOLDER/.n8n, so the folder is \$HOME, not ~/.n8n.
export N8N_USER_FOLDER="\${N8N_USER_FOLDER:-\$HOME}"
export N8N_RUNNERS_ENABLED="\${N8N_RUNNERS_ENABLED:-true}"
# Booths are reached over plain HTTP. The secure-cookie default rejects that.
export N8N_SECURE_COOKIE="\${N8N_SECURE_COOKIE:-false}"

mkdir -p "\$N8N_USER_FOLDER/.n8n"
chmod 700 "\$N8N_USER_FOLDER/.n8n" 2>/dev/null || true

# +sandbox sets N8N_SANDBOX_PORT; start-n8n-sandbox writes the URL and key here.
SANDBOX_ENV="\$N8N_USER_FOLDER/.n8n/sandbox/n8n.env"
if [[ -n "\${N8N_SANDBOX_PORT:-}" && -r "\$SANDBOX_ENV" ]]; then
  set -a
  source "\$SANDBOX_ENV"
  set +a
fi
# +search sets N8N_SEARXNG_PORT; SearXNG answers there once start-n8n-search runs.
if [[ -n "\${N8N_SEARXNG_PORT:-}" ]]; then
  export N8N_INSTANCE_AI_SEARXNG_URL="\${N8N_INSTANCE_AI_SEARXNG_URL:-http://127.0.0.1:\${N8N_SEARXNG_PORT}}"
fi
echo \$\$ > /tmp/n8n.pid
echo "Starting n8n on http://localhost:\$PORT ..."
exec n8n start
STARTER
chmod 755 "${STARTER_FILE}"

cat > "${STOPPER_FILE}" <<'STOP'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f /tmp/n8n.pid ]]; then
  pid="$(cat /tmp/n8n.pid)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f /tmp/n8n.pid
fi
STOP
chmod 755 "${STOPPER_FILE}"

# The Assistant's code sandbox is n8n's sandbox service: an API, a privileged
# Docker-in-Docker runner, and the sandbox containers that runner starts. It
# only runs on Docker, so +sandbox requires dind. Adapted from n8n's
# docker/get-n8n-compose.yml and get-n8n.sh. Not started by this script.
cat > "${SANDBOX_STARTER_FILE}" <<'SANDBOX'
#!/usr/bin/env bash
# start-n8n-sandbox [--env-only]
#   --env-only  write the keys and n8n's settings, do not start containers
set -euo pipefail

VERSION="${N8N_SANDBOX_VERSION:-1.3.4}"
PORT="${N8N_SANDBOX_PORT:-21280}"
DIR="${N8N_USER_FOLDER:-$HOME}/.n8n/sandbox"
mkdir -p "$DIR"
chmod 700 "$DIR"

# Generated once. +persist keeps them with the rest of ~/.n8n.
if [[ ! -s "$DIR/keys.env" ]]; then
  gen() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
  (umask 077; printf 'SANDBOX_API_KEY=%s\nREGISTRATION_TOKEN=%s\nRUNNER_KEY=%s\n' "$(gen)" "$(gen)" "$(gen)" > "$DIR/keys.env")
fi
source "$DIR/keys.env"

(umask 077; cat > "$DIR/n8n.env" <<EOF
N8N_INSTANCE_AI_SANDBOX_ENABLED=true
N8N_INSTANCE_AI_SANDBOX_PROVIDER=n8n-sandbox
N8N_SANDBOX_SERVICE_URL=http://127.0.0.1:${PORT}
N8N_SANDBOX_SERVICE_API_KEY=${SANDBOX_API_KEY}
EOF
)
[[ "${1:-}" == "--env-only" ]] && exit 0

(umask 077; cat > "$DIR/service.env" <<EOF
SANDBOX_API_KEYS=${SANDBOX_API_KEY}
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=${REGISTRATION_TOKEN}
SANDBOX_RUNNER_REGISTRATION_TOKEN=${REGISTRATION_TOKEN}
SANDBOX_API_RUNNER_API_KEY=${RUNNER_KEY}
SANDBOX_RUNNER_API_KEYS=${RUNNER_KEY}
EOF
)

IMG="ghcr.io/n8n-io/n8n-sandbox-service"
cat > "$DIR/compose.yml" <<EOF
# Written by start-n8n-sandbox. Regenerated on every start.
name: n8n-sandbox
volumes:
  sandbox-tls:
services:
  sandbox-certs:
    image: ${IMG}-api:${VERSION}
    user: '0:0'
    entrypoint: ['sh', '-c']
    command:
      - >
        bootstrap-mtls.sh --out-dir /tls --api-san sandbox-api
        --control-san-prefix sandbox-runner --world-readable &&
        chown -R sandbox-api:sandbox-api /tls/api && chmod -R a+rX /tls
    environment:
      NUM_RUNNERS: '1'
    volumes:
      - sandbox-tls:/tls
  sandbox-api:
    image: ${IMG}-api:${VERSION}
    depends_on:
      sandbox-certs:
        condition: service_completed_successfully
    env_file: service.env
    environment:
      SANDBOX_API_GRPC_TLS_CERT_FILE: /tls/api/grpc-server.crt
      SANDBOX_API_GRPC_TLS_KEY_FILE: /tls/api/grpc-server.key
      SANDBOX_API_GRPC_TLS_CLIENT_CA_FILE: /tls/api/ca.crt
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_CA_FILE: /tls/api/ca.crt
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_CERT_FILE: /tls/api/control-grpc-api-client.crt
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_KEY_FILE: /tls/api/control-grpc-api-client.key
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_SERVER_NAME: sandbox-runner-1
    volumes:
      - sandbox-tls:/tls:ro
    healthcheck:
      test: ['CMD', 'wget', '-qO-', 'http://localhost:8080/healthz']
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s
    # Loopback only. A DinD booth shares this network, so n8n sees it as localhost.
    ports:
      - '127.0.0.1:${PORT}:8080'
  sandbox-runner-1:
    image: ${IMG}-runner-dind:${VERSION}
    privileged: true
    depends_on:
      sandbox-api:
        condition: service_healthy
    env_file: service.env
    environment:
      SANDBOX_RUNNER_API_GRPC_ADDR: sandbox-api:9090
      SANDBOX_RUNNER_HTTP_BASE_URL: https://sandbox-runner-1:8080
      SANDBOX_RUNNER_CONTROL_GRPC_LISTEN_ADDR: ':9091'
      SANDBOX_RUNNER_CONTROL_GRPC_ADVERTISE_ADDR: sandbox-runner-1:9091
      SANDBOX_RUNNER_ID: runner-1
      SANDBOX_RUNNER_DOCKER_SANDBOX_IMAGE: ${IMG}-sandbox:${VERSION}
      SANDBOX_RUNNER_REGISTRATION_GRPC_CA_FILE: /tls/runner/ca.crt
      SANDBOX_RUNNER_REGISTRATION_GRPC_CERT_FILE: /tls/runner/grpc-client.crt
      SANDBOX_RUNNER_REGISTRATION_GRPC_KEY_FILE: /tls/runner/grpc-client.key
      SANDBOX_RUNNER_REGISTRATION_GRPC_SERVER_NAME: sandbox-api
      SANDBOX_RUNNER_CONTROL_GRPC_TLS_CERT_FILE: /tls/runner/control-grpc-server.crt
      SANDBOX_RUNNER_CONTROL_GRPC_TLS_KEY_FILE: /tls/runner/control-grpc-server.key
      SANDBOX_RUNNER_CONTROL_GRPC_TLS_CLIENT_CA_FILE: /tls/runner/ca.crt
    volumes:
      - sandbox-tls:/tls:ro
EOF

echo "Starting the n8n sandbox service ${VERSION} on http://127.0.0.1:${PORT} ..."
docker compose -f "$DIR/compose.yml" up -d
for _ in $(seq 120); do
  if curl -fsS --retry 0 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    echo "n8n sandbox service is ready."
    exit 0
  fi
  sleep 2
done
echo "n8n sandbox service did not answer /healthz on port ${PORT}" >&2
docker compose -f "$DIR/compose.yml" ps >&2 || true
exit 1
SANDBOX
chmod 755 "${SANDBOX_STARTER_FILE}"

cat > "${SANDBOX_STOPPER_FILE}" <<'SANDBOXSTOP'
#!/usr/bin/env bash
set -euo pipefail
DIR="${N8N_USER_FOLDER:-$HOME}/.n8n/sandbox"
[[ -r "$DIR/compose.yml" ]] && docker compose -f "$DIR/compose.yml" down
SANDBOXSTOP
chmod 755 "${SANDBOX_STOPPER_FILE}"

# Web search for the Assistant: SearXNG with its JSON API on (the stock image
# serves HTML only). Same settings n8n's get-n8n.sh writes. +search starts it.
cat > "${SEARCH_STARTER_FILE}" <<'SEARCH'
#!/usr/bin/env bash
# start-n8n-search
set -euo pipefail

VERSION="${N8N_SEARXNG_VERSION:-2026.9.30-a9d990033}"
PORT="${N8N_SEARXNG_PORT:-21281}"
DIR="${N8N_USER_FOLDER:-$HOME}/.n8n/searxng"
mkdir -p "$DIR"
chmod 700 "$DIR"

if [[ ! -s "$DIR/secret.env" ]]; then
  (umask 077; printf 'SEARXNG_SECRET=%s\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$DIR/secret.env")
fi

# The settings travel inline (configs.content), not as a bind mount: the Docker
# daemon is the DinD sidecar, which cannot see this booth's files.
cat > "$DIR/compose.yml" <<EOF
# Written by start-n8n-search. Regenerated on every start.
name: n8n-search
configs:
  searxng-settings:
    content: |
      use_default_settings: true
      search:
        formats:
          - html
          - json
services:
  searxng:
    image: ghcr.io/searxng/searxng:${VERSION}
    env_file: secret.env
    configs:
      - source: searxng-settings
        target: /etc/searxng/settings.yml
    # Loopback only. A DinD booth shares this network, so n8n sees it as localhost.
    ports:
      - '127.0.0.1:${PORT}:8080'
EOF

echo "Starting SearXNG ${VERSION} on http://127.0.0.1:${PORT} ..."
docker compose -f "$DIR/compose.yml" up -d
for _ in $(seq 90); do
  if curl -fsS --retry 0 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    echo "SearXNG is ready."
    exit 0
  fi
  sleep 2
done
echo "SearXNG did not answer /healthz on port ${PORT}" >&2
docker compose -f "$DIR/compose.yml" logs --tail 30 >&2 || true
exit 1
SEARCH
chmod 755 "${SEARCH_STARTER_FILE}"

cat > "${SEARCH_STOPPER_FILE}" <<'SEARCHSTOP'
#!/usr/bin/env bash
set -euo pipefail
DIR="${N8N_USER_FOLDER:-$HOME}/.n8n/searxng"
[[ -r "$DIR/compose.yml" ]] && docker compose -f "$DIR/compose.yml" down
SEARCHSTOP
chmod 755 "${SEARCH_STOPPER_FILE}"

cat > "${PROFILE_FILE}" <<PROFILE
# Profile: n8n ${REQ_VER}
export N8N_PORT="\${N8N_PORT:-${N8N_PORT}}"
export N8N_USER_FOLDER="\${N8N_USER_FOLDER:-\$HOME}"

#   start-n8n [PORT]     # foreground; +autostart nohups this
#   stop-n8n
#   start-n8n-sandbox / stop-n8n-sandbox   # Assistant code sandbox (+sandbox, needs dind)
#   start-n8n-search / stop-n8n-search     # Assistant web search, SearXNG (+search, needs dind)
#   Data: ~/.n8n  (SQLite). Select +persist to keep it across booth runs.
#   URL:  http://localhost:${N8N_PORT}
PROFILE
chmod 644 "${PROFILE_FILE}"

# Register a desktop icon that opens n8n in a browser (desktop variants only).
cb-web-icon.sh --id n8n --name "n8n" --icon applications-internet \
  --port-env N8N_PORT --port "${N8N_PORT}" \
  --path / --start start-n8n

echo ""
echo "✅ n8n installed."
echo -n "   n8n → "; n8n --version 2>/dev/null || true
echo "   Port:    ${N8N_PORT}"
echo "   Starter: ${STARTER_FILE}"
echo ""
echo "ℹ️ Ready to use:"
echo "   start-n8n [PORT]"
echo "   Access: http://localhost:${N8N_PORT}"
echo "   Workflows live in ~/.n8n. Select +persist to keep them, +autostart to"
echo "   run on boot, and +expose to publish the port on the host."
echo "   Docs: https://docs.n8n.io/"
