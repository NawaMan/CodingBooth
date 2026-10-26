#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--zls--setup.sh — Install zls, the Zig language server, matched to the installed Zig.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # the newest zls for the installed Zig (latest without Zig)
  $0 --version 0.16.1      # pin a release

Notes:
- Installs the binary to /usr/local/bin/zls
- zls X.Y.* works with Zig X.Y.* only, so the default follows \`zig version\`
- Checks the sha256 that GitHub records for the release asset, when the API answers
- Supports amd64 and arm64
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

ZLS_FALLBACK_VER="0.16.1"
REQ_VER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

case "$(uname -m)" in
  x86_64|amd64)  ASSET="zls-x86_64-linux.tar.xz" ;;
  aarch64|arm64) ASSET="zls-aarch64-linux.tar.xz" ;;
  *) echo "❌ Unsupported arch: $(uname -m) (need x86_64 or aarch64)" >&2; exit 1 ;;
esac

# No pin: take the newest zls release for the installed Zig's X.Y. A dev build of
# Zig (0.17.0-dev...) or no Zig at all takes the newest release.
API="https://api.github.com/repos/zigtools/zls/releases"
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
RELEASES_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "${API}?per_page=30" 2>/dev/null || true)
if [[ -z "$REQ_VER" ]]; then
  ZIG_VER="$(zig version 2>/dev/null || true)"
  if [[ "$ZIG_VER" =~ $VERSION_RE ]]; then
    REQ_VER=$(jq -r --arg mm "${ZIG_VER%.*}." \
              '[.[] | select(.prerelease | not) | .tag_name | select(startswith($mm))][0] // empty' \
              <<<"$RELEASES_JSON" 2>/dev/null || true)
    [[ -n "$REQ_VER" ]] || echo "⚠️  No zls release found for Zig ${ZIG_VER}; using the newest."
  fi
  REQ_VER="${REQ_VER:-latest}"
fi
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(jq -r '[.[] | select(.prerelease | not) | .tag_name][0] // empty' <<<"$RELEASES_JSON" 2>/dev/null || true)
  if [[ -z "$VERSION" ]]; then
    echo "⚠️  Could not resolve the latest zls release; using ${ZLS_FALLBACK_VER}."
    VERSION="$ZLS_FALLBACK_VER"
  fi
else
  VERSION="$REQ_VER"
fi
if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a zls version: '${VERSION}' (expected X.Y.Z, for example 0.16.1)" >&2
  exit 2
fi

EXPECTED=$(jq -r --arg v "$VERSION" --arg a "$ASSET" \
           '.[] | select(.tag_name == $v) | .assets[]? | select(.name == $a) | .digest // empty' \
           <<<"$RELEASES_JSON" 2>/dev/null | sed 's/^sha256://' || true)

URL="https://github.com/zigtools/zls/releases/download/${VERSION}/${ASSET}"
echo "⬇️  Installing zls ${VERSION} (${ASSET}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${URL}" >&2
  exit 1
fi

if [[ -n "$EXPECTED" ]]; then
  ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')"
  if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
    exit 1
  fi
else
  echo "⚠️  GitHub did not report a sha256 for ${ASSET}; installing it unverified."
fi

tar -xJf "$TMP/$ASSET" -C "$TMP" zls
install -m 755 "$TMP/zls" /usr/local/bin/zls

echo "✅ zls installed."
echo -n "   zls → "; zls --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: zls
- Fresh, Helix, TTT, and Neovim pick it up for Zig files

Notes:
- zls only understands the Zig X.Y it was released for; rebuild after changing ZIG_VERSION.
- See: https://github.com/zigtools/zls
EON
