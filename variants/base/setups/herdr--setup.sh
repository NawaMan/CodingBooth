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
  $0                           # install latest herdr
  $0 --version 0.6.10          # pin specific version

Notes:
- Installs Herdr (agent multiplexer / "tmux for AI agents") as a single static binary.
- Binary name: herdr
- See: https://herdr.dev/
- Perfect companion for claude-code, codex, aider, grok, oh-my-pi, etc.
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
  amd64) HERDR_ARCH="x86_64" ;;
  arm64) HERDR_ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/ogulcancelik/herdr/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
else
  VERSION="${REQ_VER#v}"
fi

echo "⬇️  Installing Herdr v${VERSION} (${HERDR_ARCH}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/herdr" "https://github.com/ogulcancelik/herdr/releases/download/v${VERSION}/herdr-linux-${HERDR_ARCH}"
install -m 755 "$TMP/herdr" /usr/local/bin/herdr

echo "✅ Herdr installed."
echo -n "   herdr → "; herdr --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Start / attach:           herdr
- Create new workspace:     (inside herdr) Ctrl+A c  or use the UI
- See panes + agent status: built-in sidebar shows agent state
- Works great with:         claude-code, codex, aider, grok, oh-my-pi, etc.
- Docs & more:              https://herdr.dev/

Herdr runs a lightweight background server + TUI inside your terminal.
It gives you persistent agent workspaces with real terminal visibility
(no interpretation layers).

Tip: Run your favorite CodingBooth AI agents inside Herdr panes for
the best "one terminal for the whole herd" experience.
EON
