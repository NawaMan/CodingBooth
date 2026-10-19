#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 2.2.0

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]
  $0 [<X.Y.Z>|latest]

Examples:
  $0                         # install the pinned default (0.6.0)
  $0 --version 0.6.0         # pin a specific version
  $0 0.6.0                   # same, in the form a Boothfile emits
  $0 --version latest        # install the latest GitHub release

Notes:
- Installs folio (EnvFolio) to /usr/local/bin/folio
- Also installs pass, which EnvFolio is built on, when it is missing
- Part of the base image: every variant already has it
- Checksums are verified against the release's SHA256SUMS
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
# No version given means the pinned default, not 'latest': the base image then
# gets the same EnvFolio on every build, and an upstream release that is not out
# yet (a draft is invisible to the API) cannot silently pick an older one.
ENVFOLIO_DEFAULT_VER="0.6.0"   # also the fallback when 'latest' cannot be resolved
REQ_VER="$ENVFOLIO_DEFAULT_VER"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    # `setup envfolio 0.6.0` in a Boothfile compiles to a positional argument,
    # so accept that spelling too.
    -*) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
    *) REQ_VER="$1"; shift ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- base deps ----
# EnvFolio is one bash script on top of pass. gpg, git, tar, gzip and tree are
# already in the base image; pass is not. --no-install-recommends keeps out
# xclip/qrencode: the clipboard is only needed for `-c`, and EnvFolio says what
# to install when it is.
MISSING=()
command -v curl >/dev/null 2>&1 || MISSING+=(curl ca-certificates)
command -v pass >/dev/null 2>&1 || MISSING+=(pass)
if [[ ${#MISSING[@]} -gt 0 ]]; then
  apt--install.sh "${MISSING[@]}"
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/NawaMan/EnvFolio/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See elixir--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest EnvFolio release; using ${ENVFOLIO_DEFAULT_VER}."
    VERSION="$ENVFOLIO_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install folio ----
# A single bash script, the same for every architecture. Since 0.4.0 the command
# (and the release asset) is `folio`; the app is still EnvFolio.
echo "⬇️  Installing EnvFolio (folio) v${VERSION} ..."
BASE_URL="https://github.com/NawaMan/EnvFolio/releases/download/v${VERSION}"
ASSET="folio"
TMP_DIR=$(mktemp -d)
curl -fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5 \
  "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/folio"

# Verify against the release's SHA256SUMS. A release without the checksum file
# leaves nothing to check, so warn rather than fail; a checksum that is present
# and wrong is fatal.
if curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/SHA256SUMS" -o "${TMP_DIR}/SHA256SUMS" 2>/dev/null; then
  EXPECTED=$(awk -v asset="$ASSET" '$2 == asset || $2 == "*"asset {print $1}' "${TMP_DIR}/SHA256SUMS" | head -1)
  if [[ -n "$EXPECTED" ]]; then
    ACTUAL=$(sha256sum "${TMP_DIR}/folio" | awk '{print $1}')
    if [[ "$EXPECTED" != "$ACTUAL" ]]; then
      echo "❌ Checksum mismatch for ${ASSET}: expected ${EXPECTED}, got ${ACTUAL}"
      rm -rf "${TMP_DIR}"
      exit 1
    fi
    echo "🔒 Checksum verified."
  else
    echo "⚠️  ${ASSET} is not listed in SHA256SUMS; skipping checksum verification."
  fi
else
  echo "⚠️  No SHA256SUMS published for v${VERSION}; skipping checksum verification."
fi

install -m 755 "${TMP_DIR}/folio" /usr/local/bin/folio
rm -rf "${TMP_DIR}"
# An image built on top of one with EnvFolio 0.3.0 or older still carries the
# old command, which no longer matches the store this one uses.
rm -f /usr/local/bin/envfolio

# ---- friendly summary ----
echo "✅ folio installed."
echo -n "   folio → "; folio version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Create the store:          folio init
- Add a text / a secret:     folio text insert gh/user   |   folio secret insert gh/token
- Run with them as env vars: folio exec --secrets gh -- gh auth status
- Move items to another booth: folio export   |   folio import

Notes:
- The store is ~/.folio (or $FOLIO_STORE_DIR) and its GPG key lives in
  ~/.gnupg; both are lost when the container is recreated. Select
  tools/envfolio+store-cache to keep them in .booth/cache/, or use
  `folio backup` / `restore`.
- See: https://github.com/NawaMan/EnvFolio
EON
