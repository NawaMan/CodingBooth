#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# wails--setup.sh — Install the Wails v3 CLI and the Linux GTK4/WebKitGTK
# toolchain it compiles against.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <tag>|latest]

Examples:
  $0                              # install latest wails3
  $0 --version v3.0.0-beta.16     # pin a Wails v3 module version
  $0 --version latest             # same as the default

Notes:
- Requires Go 1.25+ (run go--setup.sh first). Node.js is required to build
  most Wails frontends (run nodejs--setup.sh).
- Installs the Linux compile stack: build-essential, pkg-config, GTK 4, and
  WebKitGTK 6.0 (the v3 default; Ubuntu 24.04 ships it).
- The wails3 binary is copied to /usr/local/bin so a non-login shell
  (booth -- cmd) finds it, not only an interactive login via GOPATH/bin.
- See: https://v3.wails.io/quick-start/installation/
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
if [[ -r "$SCRIPT_DIR/libs/skip-setup.sh" ]]; then
  source "$SCRIPT_DIR/libs/skip-setup.sh"
else
  source "${SETUP_LIBS_DIR}/skip-setup.sh"
fi

REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- guards ----
if [[ ! -x /usr/local/go-current/bin/go ]] && ! command -v go >/dev/null 2>&1; then
  skip_setup "$SCRIPT_NAME" "Go is not installed (run go--setup.sh first)"
fi

# ---- Linux compile stack (GTK4 + WebKitGTK 6.0, Ubuntu 24.04+) ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  pkg-config \
  libgtk-4-dev \
  libwebkitgtk-6.0-dev
rm -rf /var/lib/apt/lists/*

if ! pkg-config --exists gtk4; then
  echo "❌ pkg-config cannot see gtk4 after installing libgtk-4-dev" >&2
  exit 1
fi
if ! pkg-config --exists webkitgtk-6.0; then
  echo "❌ pkg-config cannot see webkitgtk-6.0 after installing libwebkitgtk-6.0-dev" >&2
  exit 1
fi

# ---- resolve the Go module version ----
MODULE="github.com/wailsapp/wails/v3/cmd/wails3"
FALLBACK_VERSION="v3.0.0-beta.16"

if [[ "$REQ_VER" == "latest" ]]; then
  SPEC="${MODULE}@latest"
else
  VER="${REQ_VER#v}"
  SPEC="${MODULE}@v${VER}"
fi

echo "📦 Installing wails3 (${SPEC}) ..."

# Install as coder so the module cache lives in the booth user's GOPATH, then
# copy the binary to /usr/local/bin. go install talks to proxy.golang.org,
# which resets often enough to fail a build; retry with backoff like go--install.sh.
install -d -o coder -g coder /home/coder/go/bin /home/coder/go/pkg /home/coder/go/src

install_cli() {
  local spec="$1"
  sudo -u coder bash -lc "go install '${spec}'"
}

attempt=1
until install_cli "$SPEC"; do
  if [[ "$REQ_VER" == "latest" && $attempt -ge 1 && "$SPEC" == "${MODULE}@latest" ]]; then
    echo "⚠️  go install @latest failed; falling back to ${FALLBACK_VERSION}." >&2
    SPEC="${MODULE}@${FALLBACK_VERSION}"
  fi
  if [[ $attempt -ge 3 ]]; then
    echo "❌ go install '${SPEC}' failed after ${attempt} attempts." >&2
    exit 1
  fi
  echo "⚠️  go install '${SPEC}' failed (attempt ${attempt}); retrying in $((attempt * 5))s..." >&2
  sleep "$((attempt * 5))"
  attempt=$((attempt + 1))
done

WAILS_SRC=""
for candidate in /home/coder/go/bin/wails3 /root/go/bin/wails3; do
  if [[ -x "$candidate" ]]; then
    WAILS_SRC="$candidate"
    break
  fi
done
if [[ -z "$WAILS_SRC" ]]; then
  echo "❌ go install succeeded but wails3 was not in GOPATH/bin" >&2
  exit 1
fi

install -m 755 "$WAILS_SRC" /usr/local/bin/wails3

# WebKitGTK 6.0 sandboxes the renderer with bubblewrap, which needs user
# namespaces a booth container does not grant. Same class of workaround as
# Chromium's --no-sandbox wrappers. Without this, a Wails Linux GUI dies at
# start with: bwrap: No permissions to create new namespace / Failed to
# fully launch dbus-proxy. The template also injects these via docker -e
# (run-args) so non-login shells and the desktop session see them; the
# profile covers an interactive login that used `setup wails` by hand.
LEVEL=65
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-wails--profile.sh"
cat > "${PROFILE_FILE}" <<'EOF'
# Profile: Wails / WebKitGTK in a container
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS="${WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS:-1}"
export WEBKIT_DISABLE_DMABUF_RENDERER="${WEBKIT_DISABLE_DMABUF_RENDERER:-1}"
EOF
chmod 644 "${PROFILE_FILE}"

echo "✅ Wails v3 CLI installed."
echo -n "   wails3: "; /usr/local/bin/wails3 version 2>&1 | head -1 || echo "?"
echo -n "   gtk4: "; pkg-config --modversion gtk4 2>/dev/null || echo "?"
echo -n "   webkitgtk-6.0: "; pkg-config --modversion webkitgtk-6.0 2>/dev/null || echo "?"
echo "   Binary: /usr/local/bin/wails3"

cat <<'INFO'
ℹ️ Ready to use:
- Check the toolchain:  wails3 doctor
- Start an app:         wails3 init -n myapp -t vanilla && cd myapp
- Build this machine:   wails3 build
- Cross-compile Windows (no Docker):  wails3 build GOOS=windows
- Cross-compile macOS / other-arch Linux: select wails+cross, then
      wails3 task setup:docker
      wails3 build GOOS=darwin GOARCH=arm64
  Running a Linux GUI binary needs a desktop variant (or DISPLAY).
  WebKitGTK sandbox is disabled in the booth (no user namespaces);
  WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 is set for that.
INFO
