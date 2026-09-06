#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# floci--setup.sh — Install the Floci CLI from GitHub releases
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest Floci CLI
  $0 --version 0.2.1         # pin specific version

Notes:
- Installs the official floci CLI to /usr/local/bin/floci
  (https://github.com/floci-io/floci-cli)
- \`floci start\` launches the AWS emulator (image floci/floci) and needs
  Docker at runtime — select the dind template, or floci+autostart which
  pulls dind in.
- Supports amd64 and arm64
- See: https://floci.io
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
REQ_VER="${REQ_VER#v}"

dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="amd64" ;;
  arm64) ARCH="arm64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)" >&2; exit 1 ;;
esac

# Known-good pin when the GitHub API is rate-limited.
FALLBACK_VERSION="0.2.1"
REPO="floci-io/floci-cli"
ASSET="floci-linux-${ARCH}"

if ! command -v curl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
              "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -1 \
            | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "⚠️  Could not resolve latest floci from GitHub (got '${VERSION:-empty}'); falling back to v${FALLBACK_VERSION}." >&2
    VERSION="$FALLBACK_VERSION"
  fi
else
  VERSION="$REQ_VER"
fi

if [[ -z "${VERSION}" ]] || ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Could not resolve floci version (got '${VERSION:-empty}')" >&2
  exit 1
fi

URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
SUMS_URL="https://github.com/${REPO}/releases/download/${VERSION}/sha256sums.txt"

echo "⬇️  Installing floci CLI v${VERSION} (${ASSET}) ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$URL" -o "$TMP/floci"
chmod +x "$TMP/floci"

if command -v sha256sum >/dev/null 2>&1; then
  curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$SUMS_URL" -o "$TMP/sha256sums.txt"
  # Release checksums look like
  #   <sha256>  ./floci-linux-amd64/floci-linux-amd64
  # Match the asset as a path basename, not as a whole field.
  EXPECTED=$(awk -v a="$ASSET" '$NF == a || $NF ~ ("/" a "$") {print $1; exit}' "$TMP/sha256sums.txt")
  if [[ -z "$EXPECTED" ]]; then
    echo "❌ No checksum entry for ${ASSET} in sha256sums.txt" >&2
    exit 1
  fi
  ACTUAL=$(sha256sum "$TMP/floci" | awk '{print $1}')
  if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "❌ Checksum mismatch for ${ASSET}" >&2
    echo "   expected: $EXPECTED" >&2
    echo "   actual:   $ACTUAL" >&2
    exit 1
  fi
  echo "   checksum verified."
fi

install -m 755 "$TMP/floci" /usr/local/bin/floci

# Point AWS clients at the local emulator once it is running. Dummy keys are
# accepted by Floci; leave an already-set value alone so a real account still
# wins if the user exported one.
PROFILE_FILE="/etc/profile.d/70-cb-floci--profile.sh"
cat > "${PROFILE_FILE}" <<'PROFILE'
# Floci local AWS emulator — default endpoint and throwaway keys.
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:${FLOCI_PORT:-4566}}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROFILE
chmod 644 "${PROFILE_FILE}"

echo "✅ Floci CLI installed."
echo -n "   floci → "; floci version 2>/dev/null | head -1 || true
echo "   Profile: ${PROFILE_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Needs Docker at runtime (select dind, or floci+autostart which pulls it in)
- Start the AWS emulator:  floci start
- Export AWS env vars:     eval $(floci env)
- Talk to it with aws:     aws s3 mb s3://my-bucket
- Stop:                    floci stop

Notes:
- The emulator listens on port 4566 (LocalStack-compatible).
- Dummy credentials (test/test) are exported in every login shell.
- Lambda, RDS, and other Docker-backed services need Docker inside the booth.
- See: https://floci.io
EON
