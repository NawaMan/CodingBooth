#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# lsp--marksman--setup.sh — Install marksman, the Markdown language server.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <YYYY-MM-DD>|latest]

Examples:
  $0                          # latest marksman
  $0 --version 2026-02-08     # pin a release

Notes:
- Installs the binary under /usr/local/lib/marksman, with a /usr/local/bin/marksman
  wrapper that runs it without ICU (.NET invariant-globalization mode)
- Checks the sha256 that GitHub records for the release asset, when the API answers
- Supports amd64 and arm64
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

MARKSMAN_FALLBACK_VER="2026-02-08"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$(uname -m)" in
  x86_64|amd64)  ASSET="marksman-linux-x64" ;;
  aarch64|arm64) ASSET="marksman-linux-arm64" ;;
  *) echo "❌ Unsupported arch: $(uname -m) (need x86_64 or aarch64)" >&2; exit 1 ;;
esac

# Releases are tagged by date. The release JSON names the tag and carries each
# asset's sha256 as "digest"; a rate-limited API degrades to the pinned release.
API="https://api.github.com/repos/artempyanykh/marksman/releases"
if [[ "$REQ_VER" == "latest" ]]; then
  RELEASE_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "${API}/latest" 2>/dev/null || true)
  VERSION=$(jq -r '.tag_name // empty' <<<"$RELEASE_JSON" 2>/dev/null || true)
  if [[ -z "$VERSION" ]]; then
    echo "⚠️  Could not resolve the latest marksman release; using ${MARKSMAN_FALLBACK_VER}."
    VERSION="$MARKSMAN_FALLBACK_VER"
    RELEASE_JSON=""
  fi
else
  VERSION="$REQ_VER"
  RELEASE_JSON=""
fi
if [[ -z "$RELEASE_JSON" ]]; then
  RELEASE_JSON=$(curl -fsSL --retry 3 --retry-delay 2 "${API}/tags/${VERSION}" 2>/dev/null || true)
fi
EXPECTED=$(jq -r --arg a "$ASSET" '.assets[]? | select(.name == $a) | .digest // empty' <<<"$RELEASE_JSON" 2>/dev/null \
           | sed 's/^sha256://' || true)

URL="https://github.com/artempyanykh/marksman/releases/download/${VERSION}/${ASSET}"
echo "⬇️  Installing marksman ${VERSION} (${ASSET}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/marksman"; then
  echo "❌ Download failed: ${URL}" >&2
  exit 1
fi

if [[ -n "$EXPECTED" ]]; then
  ACTUAL="$(sha256sum "$TMP/marksman" | awk '{ print $1 }')"
  if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
    exit 1
  fi
else
  echo "⚠️  GitHub did not report a sha256 for ${ASSET}; installing it unverified."
fi

# marksman is a self-contained .NET build, and .NET aborts at startup when it
# finds no ICU — which the base image does not carry. Markdown navigation needs
# no culture data, so run it in invariant-globalization mode instead of pulling
# libicu (whose package name changes with every Ubuntu release).
install -d /usr/local/lib/marksman
install -m 755 "$TMP/marksman" /usr/local/lib/marksman/marksman
cat > /usr/local/bin/marksman <<'WRAP'
#!/bin/sh
# Installed by lsp--marksman--setup.sh. .NET needs ICU unless told otherwise.
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT="${DOTNET_SYSTEM_GLOBALIZATION_INVARIANT:-1}"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT
exec /usr/local/lib/marksman/marksman "$@"
WRAP
chmod 755 /usr/local/bin/marksman

echo "✅ marksman installed."
echo -n "   marksman → "; marksman --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: marksman server
- Fresh, Helix, and neovim+lsp pick it up for Markdown files

Notes:
- Wiki-links, heading navigation, and broken-link diagnostics for Markdown.
- See: https://github.com/artempyanykh/marksman
EON
