#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Point the Homebrew formula (NawaMan/homebrew-tap, Formula/codingbooth.rb) at a
# release's `booth` wrapper: rewrites its `url` and `sha256`. The
# `Bump Homebrew formula` workflow runs it (dispatched by hand after a release);
# it also works by hand on a tap clone.
#
# The sha256 is taken from the PUBLISHED asset, not the local file, because the
# formula's users download the published one. Given a local file too, the two
# must match. The formula has no `version` line: Homebrew reads the version from
# the URL path. Plan: docs/HOMEBREW.md, Phase 3.
#
# Prints "changed" or "unchanged" as its last line. Rerunning it for the same
# release changes nothing.
#
# CB_RELEASE_DOWNLOAD_BASE overrides where the asset is downloaded from (tests use
# a file:// URL); the formula always gets the github.com URL.

set -euo pipefail

RELEASE_BASE="https://github.com/NawaMan/CodingBooth/releases/download"
DOWNLOAD_BASE="${CB_RELEASE_DOWNLOAD_BASE:-$RELEASE_BASE}"

show_help() {
    cat <<EOF
Usage: ./build/bump-homebrew-formula.sh <version> <formula.rb> [<local booth>]

  <version>      a stable release, X.Y.Z (no --rcN)
  <formula.rb>   the formula to rewrite, e.g. homebrew-tap/Formula/codingbooth.rb
  <local booth>  optional: the wrapper that was uploaded; its sha256 must match
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then show_help; exit 0; fi
if [[ $# -lt 2 || $# -gt 3 ]]; then show_help >&2; exit 2; fi

VERSION="$1"
FORMULA="$2"
LOCAL_BOOTH="${3:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Not a stable release version: '$VERSION' (want X.Y.Z)" >&2
    exit 2
fi
if [[ ! -f "$FORMULA" ]]; then
    echo "❌ No formula at $FORMULA" >&2
    exit 1
fi

# Exactly one of each, at the formula's top level (two-space indent). The
# livecheck block's `url :stable` is deeper and unquoted, so it never matches.
for key in url sha256; do
    count=$(grep -cE "^  ${key} \"[^\"]*\"\$" "$FORMULA" || true)
    if [[ "$count" != 1 ]]; then
        echo "❌ Expected one top-level '${key} \"...\"' line in $FORMULA, found ${count}" >&2
        exit 1
    fi
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
        "${DOWNLOAD_BASE}/${VERSION}/booth" -o "$TMP/booth"; then
    echo "❌ Could not download ${DOWNLOAD_BASE}/${VERSION}/booth" >&2
    exit 1
fi
SHA=$(sha256sum "$TMP/booth" | awk '{print $1}')

if ! head -c 4096 "$TMP/booth" | grep -q '^VERSION='; then
    echo "❌ ${VERSION}/booth does not look like the booth wrapper (no VERSION= line)" >&2
    exit 1
fi
if [[ -n "$LOCAL_BOOTH" ]]; then
    LOCAL_SHA=$(sha256sum "$LOCAL_BOOTH" | awk '{print $1}')
    if [[ "$LOCAL_SHA" != "$SHA" ]]; then
        echo "❌ The published booth (${SHA}) is not the local ${LOCAL_BOOTH} (${LOCAL_SHA})" >&2
        exit 1
    fi
fi

URL="${RELEASE_BASE}/${VERSION}/booth"
cp "$FORMULA" "$TMP/before.rb"
sed -i.bak -E \
    -e "s#^  url \"[^\"]*\"\$#  url \"${URL}\"#" \
    -e "s#^  sha256 \"[^\"]*\"\$#  sha256 \"${SHA}\"#" \
    "$FORMULA"
rm -f "${FORMULA}.bak"

echo "url    ${URL}"
echo "sha256 ${SHA}"
if cmp -s "$TMP/before.rb" "$FORMULA"; then
    echo "unchanged"
else
    echo "changed"
fi
