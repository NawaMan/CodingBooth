#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.0.0

# glow--setup.sh — Install glow, Charm's terminal Markdown renderer, from
# GitHub releases.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest stable glow
  $0 --version 3.0.0       # pin a release

Notes:
- Installs glow to /usr/local/bin/glow, with its man page and
  bash/zsh/fish completions
- Checks the release's checksums.txt before installing
- Supports amd64 and arm64
- Part of the base image: every variant already has it
USAGE
}

# ---- defaults / args ----
GLOW_FALLBACK_VER="3.0.0"   # used when 'latest' cannot be resolved
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Checked before the root guard, so a typo fails the same way for everyone.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
REQ_VER="${REQ_VER#v}"
if [[ "$REQ_VER" != "latest" ]] && ! [[ "$REQ_VER" =~ $VERSION_RE ]]; then
  echo "❌ Not a glow version: '${REQ_VER}' (expected X.Y.Z, for example 3.0.0)" >&2
  exit 2
fi

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# Release assets use x86_64 / arm64.
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: ${dpkgArch} (need amd64 or arm64)" >&2; exit 1 ;;
esac

# The base image already carries these; only pay for apt somewhere leaner.
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar coreutils
  rm -rf /var/lib/apt/lists/*
fi

# Tags are vX.Y.Z. A rate-limited API falls back to the pinned release.
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              https://api.github.com/repos/charmbracelet/glow/releases/latest 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest glow release; using ${GLOW_FALLBACK_VER}."
    VERSION="$GLOW_FALLBACK_VER"
  fi
else
  VERSION="$REQ_VER"
fi

BASE_URL="https://github.com/charmbracelet/glow/releases/download/v${VERSION}"
STEM="glow_${VERSION}_Linux_${ARCH}"
ASSET="${STEM}.tar.gz"

echo "⬇️  Installing glow ${VERSION} (${ARCH}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ASSET}" -o "$TMP/$ASSET"; then
  echo "❌ Download failed: ${BASE_URL}/${ASSET}" >&2
  exit 1
fi
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/checksums.txt" -o "$TMP/checksums.txt"; then
  echo "❌ No checksums.txt published for v${VERSION}; refusing to install unverified bytes." >&2
  exit 1
fi

# checksums.txt is "<hash>  <asset>" for every asset. Compare ours only.
EXPECTED="$(awk -v a="$ASSET" '$2 == a { print $1; exit }' "$TMP/checksums.txt")"
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ SHA256 mismatch for ${ASSET} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
  exit 1
fi

"$(dirname "$0")/cb-check-tar-extract.sh" || exit 1
tar -xzf "$TMP/$ASSET" -C "$TMP"
SRC="$TMP/$STEM"
if [[ ! -f "$SRC/glow" ]]; then
  echo "❌ glow archive did not contain ${STEM}/glow" >&2
  exit 1
fi
install -m 755 "$SRC/glow" /usr/local/bin/glow

# Man page and completions are extras: a release that drops one still installs.
[[ -f "$SRC/manpages/glow.1.gz" ]] \
  && install -D -m 644 "$SRC/manpages/glow.1.gz" /usr/local/share/man/man1/glow.1.gz
[[ -f "$SRC/completions/glow.bash" ]] \
  && install -D -m 644 "$SRC/completions/glow.bash" /usr/share/bash-completion/completions/glow
[[ -f "$SRC/completions/glow.zsh" ]] \
  && install -D -m 644 "$SRC/completions/glow.zsh" /usr/local/share/zsh/site-functions/_glow
[[ -f "$SRC/completions/glow.fish" ]] \
  && install -D -m 644 "$SRC/completions/glow.fish" /usr/share/fish/vendor_completions.d/glow.fish

echo "✅ glow installed."
echo -n "   glow → "; glow --version </dev/null 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Render a file:          glow README.md
- Page through it:        glow -p README.md
- Browse a folder:        glow              (a TUI listing every .md under it)

Notes:
- For Markdown in a browser instead, use viewmd.
- A piped stdin wins over a file argument: in a script or `booth -- glow FILE`,
  add </dev/null or glow renders the (empty) pipe instead of FILE.
- Docs: https://github.com/charmbracelet/glow
EON
