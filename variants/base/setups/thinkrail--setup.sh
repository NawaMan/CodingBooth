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
  $0 [--version <X.Y.Z>|latest] [--port <PORT>]

Options:
  --version <ver>   ThinkRail release to install (default: latest stable)
  --port <PORT>     Port the web UI listens on (default: 24242)

Examples:
  $0                          # latest stable, port 24242
  $0 --version 0.2.0          # pin a release
  $0 --port 24300             # serve the web UI on another port

Notes:
- Installs the ThinkRail CLI (JetBrains' agentic IDE, https://github.com/JetBrains/thinkrail)
  to /usr/local/bin/thinkrail, checked against the release's SHA256SUMS.
- The CLI serves the whole app as a web UI; start-thinkrail binds it to
  0.0.0.0 so a published port reaches it from the host browser.
- Sign in with JetBrains AI from the UI, or use pi provider credentials.
- App state lives in ~/.thinkrail.
- Supports amd64 and arm64.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
THINKRAIL_DEFAULT_VER="0.2.0"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
THINKRAIL_PORT="24242"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --port)    shift; THINKRAIL_PORT="${1:-24242}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

STARTER_FILE="/usr/local/bin/start-thinkrail"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates coreutils
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
# releases/latest skips the -nightly.N prereleases, so 'latest' is the stable channel.
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/JetBrains/thinkrail/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # The GitHub API is rate-limited; degrade to the pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest ThinkRail release; using ${THINKRAIL_DEFAULT_VER}."
    VERSION="$THINKRAIL_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install thinkrail ----
ASSET="thinkrail-linux-${ARCH}"
BASE_URL="https://github.com/JetBrains/thinkrail/releases/download/v${VERSION}"
echo "⬇️  Installing ThinkRail v${VERSION} (${ARCH}) ..."
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ASSET}"     -o "${TMP_DIR}/${ASSET}"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/SHA256SUMS"   -o "${TMP_DIR}/SHA256SUMS"

EXPECTED="$(awk -v a="$ASSET" '$2 == a || $2 == "*"a { print $1 }' "${TMP_DIR}/SHA256SUMS")"
ACTUAL="$(sha256sum "${TMP_DIR}/${ASSET}" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ Checksum mismatch for ${ASSET} (expected '${EXPECTED:-<missing>}', got '${ACTUAL}')"
  exit 1
fi

install -m 755 "${TMP_DIR}/${ASSET}" /usr/local/bin/thinkrail
rm -rf "${TMP_DIR}"

# ---- create starter script (foreground launch) ----
# Bind 0.0.0.0, not ThinkRail's localhost default: a published port (-p) reaches
# the container's interface, never its loopback. --no-open: there is no browser
# in the container to open. The code folder is opened as the project when it is
# a git repo, which is what ThinkRail's worktree workspaces build on.
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-${THINKRAIL_PORT:-__THINKRAIL_PORT__}}
[[ $# -gt 0 ]] && shift

PROJECT=()
CODE_DIR="${HOME}/code"
if [[ $# -eq 0 ]] && git -C "$CODE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  PROJECT=("$CODE_DIR")
fi

echo "Starting ThinkRail on http://localhost:$PORT ..."
exec thinkrail --host 0.0.0.0 --port "$PORT" --no-open "${PROJECT[@]}" "$@"
STARTER
sed -i "s/__THINKRAIL_PORT__/${THINKRAIL_PORT}/g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# Register a desktop icon that opens ThinkRail in a browser (desktop variants only).
cb-web-icon.sh --id thinkrail --name "ThinkRail" --icon "applications-development" \
  --port "${THINKRAIL_PORT}" --path / --start start-thinkrail

# ---- friendly summary ----
echo "✅ ThinkRail installed."
echo -n "   thinkrail → "; thinkrail --version 2>/dev/null || true
echo "   Port:     ${THINKRAIL_PORT}"
echo "   Starter:  ${STARTER_FILE}"

cat <<EON
ℹ️ Ready to use:
- Try: start-thinkrail            # serve the web UI on port ${THINKRAIL_PORT}
- Open: http://localhost:${THINKRAIL_PORT}  (publish the port, e.g. the thinkrail+expose extension)
- Sign in with JetBrains AI in the UI, or bring your own provider via pi

Notes:
- ThinkRail runs the pi coding agent in git-worktree workspaces.
- See: https://github.com/JetBrains/thinkrail
EON
