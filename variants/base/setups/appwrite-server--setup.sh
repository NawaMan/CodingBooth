#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# appwrite-server--setup.sh — Install start/stop wrappers for self-hosted Appwrite.
# Appwrite has no native install: it is a Docker Compose stack. This script does
# not pull images at build time. start-appwrite runs the official installer
# against Docker-in-Docker at runtime.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>] [--http-port <port>] [--https-port <port>] [--data clean|seed|persist]

Examples:
  $0                                      # Appwrite 1.9.6 on 8080 / 8443, clean data
  $0 --version 1.9.6 --http-port 8080     # pin version and HTTP port
  $0 --data persist                       # dump/restore via ~/.appwrite-server (needs +persist)

Notes:
- Appwrite is Docker-only (no native / apt install). Needs dind at runtime.
- Does NOT start the stack during image build.
- Console: http://localhost:<http-port>
- The official installer CLI rejects ports longer than 4 digits (20080 fails;
  8080 / 8443 / 80 / 443 are fine).
- --data clean (default): wipe Compose volumes each start.
  seed: restore ~/.appwrite-server (home-seed), do not copy back.
  persist: restore and dump ~/.appwrite-server (.booth/cache bind).
- Pair with setup appwrite-cli for the CLI.
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

VERSION="1.9.6"
HTTP_PORT="8080"
HTTPS_PORT="8443"
DATA_MODE="clean"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)    shift; VERSION="${1:-1.9.6}"; shift ;;
    --http-port)  shift; HTTP_PORT="${1:-8080}"; shift ;;
    --https-port) shift; HTTPS_PORT="${1:-8443}"; shift ;;
    --data)       shift; DATA_MODE="${1:-clean}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
VERSION="${VERSION#v}"
[[ "$VERSION" == "latest" ]] && VERSION="1.9.6"
DATA_MODE="$(echo "$DATA_MODE" | tr '[:upper:]' '[:lower:]')"
case "$DATA_MODE" in
  clean|seed|persist) ;;
  *)
    echo "⚠️  Unknown --data ${DATA_MODE}; using clean." >&2
    DATA_MODE="clean"
    ;;
esac

if [[ ${#HTTP_PORT} -gt 4 || ${#HTTPS_PORT} -gt 4 ]]; then
  echo "⚠️  Appwrite's installer rejects ports longer than 4 digits (got HTTP=${HTTP_PORT} HTTPS=${HTTPS_PORT})." >&2
  echo "    Use 8080 / 8443 / 80 / 443. Falling back to 8080 and 8443." >&2
  HTTP_PORT="8080"
  HTTPS_PORT="8443"
fi

STARTER_FILE="/usr/local/bin/start-appwrite"
STOPPER_FILE="/usr/local/bin/stop-appwrite"
LIB_FILE="/usr/local/lib/cb-appwrite-data.sh"
PROFILE_FILE="/etc/profile.d/70-cb-appwrite-server--profile.sh"

export BAKED_VERSION="$VERSION"
export BAKED_HTTP_PORT="$HTTP_PORT"
export BAKED_HTTPS_PORT="$HTTPS_PORT"
export BAKED_DATA="$DATA_MODE"

mkdir -p /usr/local/lib

# Runtime $HOME / $APPWRITE_* survive; baked version, ports, and data mode are stamped.
# Do NOT call dind-open-port here: a DinD booth shares the sidecar netns, so
# Traefik's published port is already on localhost. Forwarding $PORT to
# ${DIND_NAME}:$PORT is a self-connect and forks socat until the box falls over.
envsubst '$BAKED_VERSION $BAKED_HTTP_PORT $BAKED_HTTPS_PORT $BAKED_DATA' <<'EOF' > "$LIB_FILE"
# shellcheck shell=bash
# Sourced by start-appwrite / stop-appwrite. Baked defaults from setup.

cb_appwrite_init() {
  VERSION="${APPWRITE_VERSION:-$BAKED_VERSION}"
  HTTP_PORT="${APPWRITE_PORT:-$BAKED_HTTP_PORT}"
  HTTPS_PORT="${APPWRITE_HTTPS_PORT:-$BAKED_HTTPS_PORT}"
  VOLUME="${APPWRITE_COMPOSE_VOLUME:-cb-appwrite-config}"
  IMAGE="appwrite/appwrite:${VERSION}"
  DATA_DIR="${APPWRITE_DATA_DIR:-$HOME/.appwrite-server}"
  MODE="$(echo "${APPWRITE_DATA:-$BAKED_DATA}" | tr '[:upper:]' '[:lower:]')"
  case "$MODE" in
    clean|seed|persist) ;;
    *) MODE="clean" ;;
  esac
}

cb_appwrite_health_url() {
  local port="$1"
  curl --retry 0 -fsS -m 3 -H "Host: localhost" \
    "http://127.0.0.1:${port}/v1/health/version" 2>/dev/null
}

cb_appwrite_health_ok() {
  cb_appwrite_health_url "$1" >/dev/null
}

cb_appwrite_wait_for_docker() {
  local i
  for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

cb_appwrite_data_is_bind() {
  local p="$DATA_DIR"
  [[ -e "$p" ]] || return 1
  awk -v p="$p" '$5 == p { found=1 } END { exit !found }' /proc/self/mountinfo 2>/dev/null
}

cb_appwrite_has_dump() {
  [[ -s "${DATA_DIR}/manifest" ]]
}

cb_appwrite_volume_names() {
  docker volume ls -q 2>/dev/null | grep -E '^(cb-appwrite-config|.*appwrite.*)$' || true
}

cb_appwrite_stop_containers() {
  local ids
  ids="$(docker ps -q --filter name=appwrite 2>/dev/null || true)"
  if [[ -n "$ids" ]]; then
    # shellcheck disable=SC2086
    docker stop $ids >/dev/null || true
  fi
  ids="$(docker ps -aq --filter name=appwrite 2>/dev/null || true)"
  if [[ -n "$ids" ]]; then
    # shellcheck disable=SC2086
    docker rm -f $ids >/dev/null || true
  fi
}

cb_appwrite_wipe_volumes() {
  cb_appwrite_stop_containers
  local vol
  for vol in $(cb_appwrite_volume_names); do
    docker volume rm -f "$vol" >/dev/null 2>&1 || true
  done
}

# Stream tarballs through docker stdout/stdin so DinD does not need a booth path mount.
cb_appwrite_dump() {
  mkdir -p "${DATA_DIR}/volumes"
  : > "${DATA_DIR}/manifest"
  local vol
  for vol in $(cb_appwrite_volume_names); do
    echo "  dumping ${vol} ..."
    if docker run --rm --entrypoint tar \
      --volume "${vol}:/from:ro" \
      "$IMAGE" -C /from -cf - . > "${DATA_DIR}/volumes/${vol}.tar"; then
      echo "$vol" >> "${DATA_DIR}/manifest"
    else
      echo "⚠️  dump failed for ${vol}" >&2
      rm -f "${DATA_DIR}/volumes/${vol}.tar"
    fi
  done
}

cb_appwrite_restore() {
  local vol tar
  [[ -s "${DATA_DIR}/manifest" ]] || return 1
  while IFS= read -r vol || [[ -n "$vol" ]]; do
    [[ -n "$vol" ]] || continue
    tar="${DATA_DIR}/volumes/${vol}.tar"
    [[ -s "$tar" ]] || continue
    echo "  restoring ${vol} ..."
    docker volume create "$vol" >/dev/null
    docker run --rm -i --entrypoint tar \
      --volume "${vol}:/to" \
      "$IMAGE" -C /to -xf - < "$tar"
  done < "${DATA_DIR}/manifest"
}

cb_appwrite_run_installer() {
  docker volume create "$VOLUME" >/dev/null
  # Official installer: equals-form flags (utopia-php CLI does not parse
  # "--http-port 8080" as a value; it needs --http-port=8080). Ports must be
  # at most 4 digits. --interactive=N skips the web wizard.
  docker run --rm \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume "${VOLUME}:/usr/src/code/appwrite" \
    --entrypoint=install \
    "$IMAGE" \
    --interactive=N \
    --http-port="${HTTP_PORT}" \
    --https-port="${HTTPS_PORT}"
}

# Do not re-run install on a restored tree: install overwrites .env (new secrets
# would not match the restored MariaDB). Compose up the dumped project instead.
cb_appwrite_compose_up() {
  docker run --rm \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume "${VOLUME}:/usr/src/code/appwrite" \
    --workdir /usr/src/code/appwrite \
    --entrypoint docker \
    "$IMAGE" \
    compose --project-directory /usr/src/code/appwrite up -d --remove-orphans
}

cb_appwrite_wait_healthy() {
  local i
  echo "Waiting for Appwrite API ..."
  for i in $(seq 1 120); do
    if cb_appwrite_health_ok "$HTTP_PORT"; then
      echo "✅ Appwrite is up: http://localhost:${HTTP_PORT}"
      cb_appwrite_health_url "$HTTP_PORT" || true
      echo
      return 0
    fi
    if cb_appwrite_health_ok 80; then
      echo "✅ Appwrite is up: http://localhost:80"
      cb_appwrite_health_url 80 || true
      echo
      return 0
    fi
    sleep 5
  done
  echo "⚠️  Appwrite did not become healthy in time." >&2
  echo "    Try: docker ps" >&2
  echo "         GET http://127.0.0.1:${HTTP_PORT}/v1/health/version  (Host: localhost)" >&2
  return 1
}

cb_appwrite_ensure_admin() {
  local email password port code
  email="${APPWRITE_ADMIN_EMAIL:-admin@example.com}"
  password="${APPWRITE_ADMIN_PASSWORD:-password123}"
  port="$HTTP_PORT"
  cb_appwrite_health_ok "$port" || port=80
  code="$(curl -sS -m 10 --retry 3 --retry-delay 2 -o /tmp/cb-appwrite-account.json -w '%{http_code}' \
    -X POST "http://127.0.0.1:${port}/v1/account" \
    -H "Host: localhost" \
    -H "Content-Type: application/json" \
    -H "X-Appwrite-Project: console" \
    -d "{\"userId\":\"unique()\",\"email\":\"${email}\",\"password\":\"${password}\",\"name\":\"Admin\"}" \
    2>/dev/null || echo 000)"
  case "$code" in
    201)
      echo "Console admin: ${email}  /  ${password}"
      ;;
    409|400)
      echo "Console admin already present (tried ${email})."
      ;;
    *)
      echo "⚠️  Could not seed console admin (HTTP ${code}). Sign up in the console." >&2
      ;;
  esac
}

cb_appwrite_resolve_mode() {
  if [[ "$MODE" == persist ]] && ! cb_appwrite_data_is_bind; then
    echo "⚠️  APPWRITE_DATA=persist but ${DATA_DIR} is not a cache bind." >&2
    echo "    Select appwrite-server+persist so cache-dirs mounts it. Using clean." >&2
    MODE="clean"
  fi
}

cb_appwrite_start_persist_watch() {
  local pidfile="/tmp/cb-appwrite-persist.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    return 0
  fi
  (
    trap 'cb_appwrite_stop_containers; cb_appwrite_dump >/tmp/cb-appwrite-dump.log 2>&1 || true; exit 0' TERM INT
    while true; do sleep 30; done
  ) &
  echo $! > "$pidfile"
}
EOF
chmod 644 "$LIB_FILE"

cat > "$STARTER_FILE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /usr/local/lib/cb-appwrite-data.sh
cb_appwrite_init

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker is not available. Select dind (appwrite-server+autostart pulls it in)." >&2
  exit 1
fi
if ! cb_appwrite_wait_for_docker; then
  echo "❌ Docker did not become ready. Is dind selected and the sidecar up?" >&2
  exit 1
fi

cb_appwrite_resolve_mode

if cb_appwrite_health_ok "$HTTP_PORT"; then
  echo "Appwrite already running on http://localhost:${HTTP_PORT}  (data=${MODE})"
  cb_appwrite_health_url "$HTTP_PORT" || true
  echo
  [[ "$MODE" == persist ]] && cb_appwrite_start_persist_watch
  exit 0
fi
if cb_appwrite_health_ok 80; then
  echo "Appwrite already running on http://localhost:80 (installer default)."
  echo "  This booth asked for ${HTTP_PORT}; curl :80 or rebuild after the port fix."
  cb_appwrite_health_url 80 || true
  echo
  [[ "$MODE" == persist ]] && cb_appwrite_start_persist_watch
  exit 0
fi

echo "Starting Appwrite ${VERSION} on http://localhost:${HTTP_PORT} (data=${MODE}) ..."
echo "  (first boot pulls the Compose stack — several minutes, ~4GB RAM)"
mkdir -p "$DATA_DIR"

case "$MODE" in
  clean)
    cb_appwrite_wipe_volumes
    cb_appwrite_run_installer
    ;;
  seed)
    cb_appwrite_wipe_volumes
    if cb_appwrite_has_dump; then
      cb_appwrite_restore
      cb_appwrite_compose_up
    else
      cb_appwrite_run_installer
    fi
    ;;
  persist)
    if cb_appwrite_has_dump; then
      cb_appwrite_wipe_volumes
      cb_appwrite_restore
      cb_appwrite_compose_up
    else
      cb_appwrite_run_installer
    fi
    ;;
esac

if ! cb_appwrite_wait_healthy; then
  echo "         GET http://127.0.0.1/v1/health/version  (Host: localhost)" >&2
  exit 1
fi

cb_appwrite_ensure_admin
[[ "$MODE" == persist ]] && cb_appwrite_start_persist_watch
exit 0
EOF
chmod 755 "$STARTER_FILE"

cat > "$STOPPER_FILE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source /usr/local/lib/cb-appwrite-data.sh
cb_appwrite_init

if ! command -v docker >/dev/null 2>&1; then
  echo "No Docker; nothing to stop."
  exit 0
fi

cb_appwrite_resolve_mode
cb_appwrite_stop_containers
if [[ "$MODE" == persist ]]; then
  echo "Dumping Appwrite volumes to ${DATA_DIR} ..."
  cb_appwrite_dump
  echo "Appwrite data saved (persist)."
fi
echo "Appwrite containers stopped."
EOF
chmod 755 "$STOPPER_FILE"

envsubst '$BAKED_HTTP_PORT' <<'EOF' > "$PROFILE_FILE"
# Appwrite self-hosted endpoint (cheap; skipped if already set).
if [ -z "${APPWRITE_ENDPOINT:-}" ]; then
  export APPWRITE_ENDPOINT="http://localhost:${APPWRITE_PORT:-$BAKED_HTTP_PORT}/v1"
fi
EOF
chmod 644 "$PROFILE_FILE"

# Desktop variants only; no-ops on base. Documents http://localhost for test90.
cb-web-icon.sh --id appwrite --name "Appwrite" --icon applications-internet \
  --port-env APPWRITE_PORT --port "${HTTP_PORT}" --path / --start start-appwrite

echo "✅ Appwrite server wrappers installed."
echo "   Version:  ${VERSION}"
echo "   HTTP:     http://localhost:${HTTP_PORT}"
echo "   HTTPS:    ${HTTPS_PORT} (self-signed; optional)"
echo "   Data:     ${DATA_MODE}"
echo "   Starter:  ${STARTER_FILE}"
echo "   Stopper:  ${STOPPER_FILE}"

cat <<EON
ℹ️ Ready to use:
- Start: start-appwrite
- Stop:  stop-appwrite
- Console: http://localhost:${HTTP_PORT}
- Health: GET http://localhost:${HTTP_PORT}/v1/health/version  (Host: localhost)
- Data:  ${DATA_MODE}  (clean | seed via +seed | persist via +persist)

Notes:
- Appwrite is a Docker Compose stack (Traefik, database, Redis, workers).
  There is no native install. Select dind; +autostart pulls it in and starts on boot.
- First start downloads many images and wants ~4GB RAM. Later starts reuse them.
- clean: empty stack every booth. seed: home-seed snapshot, writes discarded.
  persist: .booth/cache bind; stop-appwrite dumps volumes for the next run.
- Default console login after first start: admin@example.com / password123
- Point the CLI at it: appwrite client --endpoint http://localhost:${HTTP_PORT}/v1 --self-signed true
- See: https://appwrite.io/docs/advanced/self-hosting/installation
EON
