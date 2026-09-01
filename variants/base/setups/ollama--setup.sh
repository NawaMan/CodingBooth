#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest Ollama
  $0 --version 0.6.2         # pin specific version

Notes:
- Downloads Ollama binary from GitHub releases
- Installs to /usr/local/bin/ollama
- Supports amd64 and arm64
- Ollama must be started manually with 'ollama serve' before use
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates zstd
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  # Unauthenticated api.github.com is rate limited to 60 requests/hour/IP. When
  # that limit is hit the body is a JSON error, no tag_name matches, and VERSION
  # comes back empty — which used to build the URL ".../download/v/ollama-..."
  # and fail as a 404 much later, naming a file rather than the real cause.
  VERSION=$(curl -fsSL --connect-timeout 10 --max-time 30 \
    --retry 3 --retry-delay 3 --retry-all-errors \
    https://api.github.com/repos/ollama/ollama/releases/latest \
    | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
else
  VERSION="$REQ_VER"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "❌ Could not resolve an Ollama version (got: '${VERSION:-<empty>}')." >&2
  echo "   api.github.com may be rate limiting this host; pin one with --version <X.Y.Z>." >&2
  exit 1
fi

# ---- download and install ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TARBALL_URL="https://github.com/ollama/ollama/releases/download/v${VERSION}/ollama-linux-${ARCH}.tar.zst"
TARBALL="$TMP/ollama.tar.zst"
echo "⬇️  Installing Ollama v${VERSION} (${ARCH}) ..."

# Name the size before starting. This tarball is ~1.4 GB and pulls at roughly
# 1 MB/s, so it is a legitimate twenty-plus-minute download — and the line above
# was the last thing this step printed for all of it. A build that prints
# nothing for twenty minutes is indistinguishable from a hung one, and the
# natural response (^C) discards the RUN layer and restarts from zero.
# Best-effort: a failed probe just means no size. Lowercase first, since HTTP/2
# sends header names lowercased but HTTP/1.1 sends "Content-Length" and mawk has
# no IGNORECASE; keep the last value, as the redirect hops carry a length of 0.
TOTAL="$(curl -fsIL --connect-timeout 10 --max-time 30 "$TARBALL_URL" 2>/dev/null \
  | tr -d '\r' | tr 'A-Z' 'a-z' \
  | awk '/^content-length:/{n=$2} END{print n}')" || true
[[ "$TOTAL" =~ ^[0-9]+$ ]] || TOTAL=0

if (( TOTAL > 0 )); then
  echo "   ollama-linux-${ARCH}.tar.zst is $((TOTAL / 1024 / 1024)) MB; this takes tens of minutes."
fi

# Start clean so -C - is purely a resume-across-retries mechanism: against a
# stale complete file the range request would come back 416 and -f would fail.
rm -f "${TARBALL}.part"

# The original fetch had no bounds at all: no connect timeout, no stall
# detection, no retry, no resume. --speed-limit/--speed-time abandon a transfer
# that has genuinely died rather than riding it until the far end hangs up;
# a slow-but-moving link stays under the threshold and is left alone. -C -
# resumes across retries, so a reset at minute twenty does not repay 1.4 GB
# from zero. --max-time is the outer bound past which something is truly wrong.
curl -fsSL --connect-timeout 10 --max-time 3600 \
  --speed-limit 1024 --speed-time 60 \
  --retry 5 --retry-delay 5 --retry-all-errors -C - \
  "$TARBALL_URL" -o "${TARBALL}.part" &
CURL_PID=$!

# curl's own --progress-bar is useless here: it rewrites a single line with \r
# and no newline, and the build progress reader keeps only what follows the last
# \r on a *completed* line (see cli/src/pkg/docker/build_progress.go). None of
# its meter ever reaches the status line. So emit our own heartbeat —
# newline-terminated, and therefore the one thing that does advance it.
while kill -0 "$CURL_PID" 2>/dev/null; do
  sleep 30
  kill -0 "$CURL_PID" 2>/dev/null || break
  GOT="$(stat -c %s "${TARBALL}.part" 2>/dev/null || echo 0)"
  if (( TOTAL > 0 )); then
    echo "   … $((GOT / 1024 / 1024)) MB of $((TOTAL / 1024 / 1024)) MB ($((GOT * 100 / TOTAL))%)"
  else
    echo "   … $((GOT / 1024 / 1024)) MB"
  fi
done

# Let curl's exit status fail the step under `set -e`; a partial tarball must
# never be handed to tar as if it were the real thing.
wait "$CURL_PID"
mv "${TARBALL}.part" "$TARBALL"

tar --zstd -xf "$TARBALL" -C "$TMP"

# Install the ollama binary (it's in bin/ inside the tarball)
install -m 755 "$TMP/bin/ollama" /usr/local/bin/ollama

# ---- startup script: create ~/.ollama for model storage ----
STARTUP_FILE="/usr/share/startup.d/70-cb-ollama--startup.sh"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
set -euo pipefail

# Ollama startup script
# Creates ~/.ollama directory for model storage

mkdir -p "$HOME/.ollama"
STARTUP
chmod 755 "${STARTUP_FILE}"

# ---- friendly summary ----
echo "✅ Ollama installed."
echo -n "   ollama → "; ollama --version 2>/dev/null || true
echo "   Startup: ${STARTUP_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Start the server: ollama serve &
- Pull a model:     ollama pull llama3
- Chat:             ollama run llama3

Notes:
- Ollama must be started with 'ollama serve' before pulling or running models.
- Models are stored in ~/.ollama (created on container start).
- GPU passthrough requires appropriate Docker flags (e.g., --gpus all).
- See: https://ollama.com/
EON
