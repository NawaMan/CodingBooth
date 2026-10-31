#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 1.1.0

# haskell-tools--setup.sh
#
# Installs Haskell developer tools as ready-made binaries instead of compiling them with
# cabal (each is a 5-15 minute build: they all pull in ghc-lib-parser).
#
# Usage: haskell-tools--setup.sh <tool>[@<version>] [...]     (space or comma separated)
#
#   hlint      linter        from CodingBoothPrebuilt (x86_64 and arm64)
#   ormolu     formatter     from CodingBoothPrebuilt (x86_64 and arm64)
#   fourmolu   formatter     upstream binary on x86_64 and arm64
#   pandoc     doc converter upstream binary on x86_64 and arm64
#
# Unversioned means upstream's latest release. Each tool lands in
# /opt/haskell-tools/<tool>-<version>, linked into /usr/local/bin. CodingBoothPrebuilt
# assets are sha256-checked; upstream publishes no checksums for these. An hlint or ormolu
# version not prebuilt (yet) is built from source with cabal, which needs the haskell setup.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }

case "${1:-}" in
  -h|--help) sed -n '9,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# shellcheck disable=SC2046
set -- $(echo "$@" | tr ',' ' ')
if [ $# -eq 0 ]; then
  echo "ℹ️  No Haskell tools requested; nothing to install."
  exit 0
fi

TOOLS_ROOT=/opt/haskell-tools

SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

case "$(uname -m)" in
  x86_64|amd64)  ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "❌ Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for spec in "$@"; do
  case "${spec%%@*}" in
    hlint|ormolu|fourmolu|pandoc) ;;
    *) echo "❌ Unknown Haskell tool '${spec%%@*}' (supported: hlint, ormolu, fourmolu, pandoc)" >&2; exit 1 ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip
rm -rf /var/lib/apt/lists/*

fetch() {
  curl --connect-timeout 15 --retry 3 --retry-delay 3 --retry-all-errors -fsSL "$1" -o "$2"
}

# Newest release tag of a GitHub repo, without a leading "v".
latest_release() {
  curl --connect-timeout 15 --retry 3 --retry-delay 3 -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"v?([^"]+)"$/\1/'
}

# hlint and ormolu come from CodingBoothPrebuilt on both CPUs (upstream builds x86_64 only),
# built weekly for the versions Stackage ships and upstream's latest; a version it lacks is
# built here with cabal, laid out the same way: the executable, plus hlint's data/ beside it,
# where hlint looks for it.
install_prebuilt_or_build() {
  local tool="$1" version="$2" dest="$3"
  if cb_prebuilt_install "$tool" "$version" native "$dest"; then
    return
  fi

  echo "ℹ️  ${tool} ${version}: building from source with cabal..."
  [ -f /etc/profile.d/99-haskell--profile.sh ] && source /etc/profile.d/99-haskell--profile.sh
  command -v cabal >/dev/null 2>&1 \
    || { echo "❌ Building ${tool} needs cabal: add the haskell setup first." >&2; exit 1; }
  # A scratch CABAL_DIR keeps the store out of root's home, where only root could read
  # hlint's data files.
  export CABAL_DIR="$TMP/cabal"
  cabal update
  cabal install "${tool}-${version}" --installdir="$dest" --install-method=copy --overwrite-policy=always
  if [ "$tool" = hlint ]; then
    (cd "$TMP" && cabal get "hlint-${version}")
    cp -r "$TMP/hlint-${version}/data" "$dest/data"
  fi
}

install_tool() {
  local tool="$1" version="$2" repo
  case "$tool" in
    hlint)    repo=ndmitchell/hlint ;;
    ormolu)   repo=tweag/ormolu ;;
    fourmolu) repo=fourmolu/fourmolu ;;
    pandoc)   repo=jgm/pandoc ;;
  esac
  if [ -z "$version" ]; then
    version="$(latest_release "$repo")"
    [ -n "$version" ] || { echo "❌ Could not look up the latest ${tool} release" >&2; exit 1; }
  fi

  local dest="${TOOLS_ROOT}/${tool}-${version}" base="https://github.com/${repo}/releases/download"
  rm -rf "$dest"
  mkdir -p "$dest"

  case "$tool:$ARCH" in
    hlint:*|ormolu:*)
      install_prebuilt_or_build "$tool" "$version" "$dest"
      ;;
    fourmolu:*)
      echo "⬇️  fourmolu ${version}: upstream ${ARCH} build"
      fetch "${base}/v${version}/fourmolu-${version}-linux-${ARCH}.zip" "$TMP/fourmolu.zip"
      # The zip holds fourmolu-<version>-linux-<arch>/fourmolu.
      unzip -oq "$TMP/fourmolu.zip" -d "$TMP/fourmolu"
      find "$TMP/fourmolu" -type f -name fourmolu -exec mv {} "$dest/fourmolu" \;
      ;;
    pandoc:*)
      local parch=amd64; [ "$ARCH" = arm64 ] && parch=arm64
      echo "⬇️  pandoc ${version}: upstream ${ARCH} build"
      fetch "${base}/${version}/pandoc-${version}-linux-${parch}.tar.gz" "$TMP/pandoc.tar.gz"
      tar -xzf "$TMP/pandoc.tar.gz" -C "$dest" --strip-components=1
      ;;
  esac

  local exe="$dest/$tool"
  [ "$tool" = pandoc ] && exe="$dest/bin/pandoc"
  chmod -R a+rX "$dest"
  chmod a+x "$exe"
  "$exe" --version >/dev/null 2>&1 || { echo "❌ ${tool} ${version} does not run on this image" >&2; exit 1; }
  ln -sfn "$exe" "/usr/local/bin/$tool"
  echo "✅ ${tool} ${version} → /usr/local/bin/${tool}"
}

for spec in "$@"; do
  tool="${spec%%@*}"
  version=""
  [ "$spec" != "$tool" ] && version="${spec#*@}"
  install_tool "$tool" "$version"
done
