#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [VERSION]

Arguments:
  VERSION  protoc-gen-prost version to install (default: 0.5.0)

Examples:
  $0            # install the default pinned version
  $0 0.4.0      # pin a different version

Notes:
- Installs protoc-gen-prost to /usr/local/bin, a standalone protoc plugin
  generating Prost! message code from .proto files.
- Comes prebuilt (sha256-checked) from https://github.com/NawaMan/CodingBoothPrebuilt
  on both CPUs (upstream publishes the crate only); a version not prebuilt (yet) is
  built with \`cargo install --locked\`, which needs the rust setup.
- See: https://github.com/neoeinstein/protoc-gen-prost
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

VERSION="${1:-0.5.0}"
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a protoc-gen-prost version: '${VERSION}' (expected X.Y.Z, for example 0.5.0)" >&2
  exit 2
fi

SETUPS_DIR="$(dirname "$0")"
[ -x "${SETUPS_DIR}/cargo--install.sh" ] || SETUPS_DIR=/opt/codingbooth/setups
SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

echo "⬇️  Installing protoc-gen-prost ${VERSION} ..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if cb_prebuilt_install protoc-gen-prost "$VERSION" native "$TMP/prebuilt"; then
  install -m 755 "$TMP/prebuilt/bin/protoc-gen-prost" /usr/local/bin/protoc-gen-prost
  LOCATION=/usr/local/bin/protoc-gen-prost
else
  echo "ℹ️  protoc-gen-prost ${VERSION}: not prebuilt for this image; building with cargo..."
  "${SETUPS_DIR}/cargo--install.sh" --locked "protoc-gen-prost@${VERSION}"
  LOCATION="~/.cargo/bin/protoc-gen-prost"
fi

echo "✅ protoc-gen-prost installed."
echo "   Version:  ${VERSION}"
echo "   Location: ${LOCATION}"

cat <<'EON'
ℹ️ Ready to use:
- Generate Prost! message code:
    protoc --prost_out=src/gen -I. file.proto
- In a Rust-only project, prost-build from a build.rs is the more common path.
EON
