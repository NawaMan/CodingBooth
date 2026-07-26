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
  $0                         # install latest OpenCode
  $0 --version 1.18.4        # pin a specific version

Notes:
- Installs OpenCode (anomalyco/SST), the open multi-provider coding agent TUI.
- Binary name: opencode
- Auth: ~/.local/share/opencode/auth.json (or /connect in the TUI)
- Config: ~/.config/opencode/opencode.json
- See: https://opencode.ai  and  https://github.com/anomalyco/opencode
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) OC_ARCH="x64" ;;
  arm64) OC_ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates tar
rm -rf /var/lib/apt/lists/*

REPO="anomalyco/opencode"
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
    | head -1 \
    | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

if [[ -z "$VERSION" ]]; then
  echo "❌ Failed to resolve OpenCode version" >&2
  exit 1
fi

# Prefer AVX2 build; fall back to baseline on older CPUs.
TARGET="linux-${OC_ARCH}"
if [[ "$OC_ARCH" == "x64" ]] && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
  TARGET="linux-x64-baseline"
fi

# Alpine/musl is uncommon in CodingBooth (Ubuntu base), but detect it.
if [[ -f /etc/alpine-release ]] || { command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; then
  TARGET="${TARGET}-musl"
fi

FILENAME="opencode-${TARGET}.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${FILENAME}"
echo "⬇️  Installing OpenCode v${VERSION} (${FILENAME}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 30 \
  -o "$TMP/opencode.tar.gz" "$URL"
tar -xzf "$TMP/opencode.tar.gz" -C "$TMP"

# Archive usually contains a single `opencode` binary at top level.
BIN=""
if [[ -f "$TMP/opencode" ]]; then
  BIN="$TMP/opencode"
else
  BIN="$(find "$TMP" -type f -name opencode | head -1 || true)"
fi
if [[ -z "$BIN" || ! -f "$BIN" ]]; then
  echo "❌ Could not find opencode binary in archive" >&2
  exit 1
fi
chmod +x "$BIN"
if ! "$BIN" --version </dev/null >/dev/null 2>&1; then
  echo "❌ Downloaded opencode failed to run; aborting install." >&2
  exit 1
fi
install -m 755 "$BIN" /usr/local/bin/opencode

STARTUP_FILE="/usr/share/startup.d/70-cb-opencode--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-opencode--profile.sh"

cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# OpenCode startup — credential seed handled by booth-entry smart_copy.
mkdir -p "$HOME/.config/opencode" "$HOME/.local/share/opencode"
EOF
chmod 755 "${STARTUP_FILE}"

cat > "${PROFILE_FILE}" <<EOF
# Profile: OpenCode v${VERSION}
#   opencode                 # interactive multi-provider coding agent
#   opencode run "prompt"    # one-shot
#
# Auth: /connect in the TUI, or seed ~/.local/share/opencode/auth.json
# Config: ~/.config/opencode/opencode.json
# Docs: https://opencode.ai
EOF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "✅ OpenCode installed."
echo "   Version: ${VERSION}"
echo "   Binary:  /usr/local/bin/opencode"
echo "   Startup: ${STARTUP_FILE}"
echo ""
echo "=== Credential Seeding ==="
echo '  run-args = ['
echo '      "-v", "~/.local/share/opencode/auth.json:/etc/cb-home-seed/.local/share/opencode/auth.json:ro",'
echo '      "-v", "~/.config/opencode/opencode.json:/etc/cb-home-seed/.config/opencode/opencode.json:ro"'
echo '  ]'
echo ""
