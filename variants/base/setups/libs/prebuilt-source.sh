# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.1

# ---- Prebuilt assets from NawaMan/CodingBoothPrebuilt ----
#
# Setups that would otherwise compile from source while the image builds (a Rust
# kernel, a webpack bundle, ...) first try a prebuilt release asset. Each tool
# version is one release, tagged <tool>-<version>, holding:
#
#   <tool>-<version>-ubuntu<ver>-<x86_64|arm64>.tar.gz   per Ubuntu + CPU ("native")
#   <tool>-<version>.tar.gz                              arch-independent ("any")
#
# plus a matching .sha256. Each tarball unpacks to a single folder named after the
# asset. https://github.com/NawaMan/CodingBoothPrebuilt has the build scripts.
#
# Source with:
#   SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
#   source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

CB_PREBUILT_URL="${CB_PREBUILT_URL:-https://github.com/NawaMan/CodingBoothPrebuilt/releases/download}"

# cb_prebuilt_asset <tool> <version> <native|any>
#   The asset name for this machine, e.g. evcxr_jupyter-0.22.0-ubuntu26.04-x86_64.
#   Fails (status 1, no output) on a CPU no asset is built for.
cb_prebuilt_asset() {
  local tool="$1" version="$2" mode="$3" arch distro
  if [[ "$mode" == any ]]; then
    echo "${tool}-${version}"
    return 0
  fi
  case "$(uname -m)" in
    x86_64|amd64)  arch=x86_64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  distro="$(. /etc/os-release && echo "${ID}${VERSION_ID}")"
  echo "${tool}-${version}-${distro}-${arch}"
}

# cb_prebuilt_install <tool> <version> <native|any> <dest-dir>
#   Downloads the asset, checks it against its .sha256, and unpacks its contents
#   into <dest-dir> (created; existing files are kept). Returns 1 without touching
#   <dest-dir> when no asset can be downloaded — not published for this version,
#   Ubuntu or CPU, or GitHub is unreachable — so the caller can build from source.
#   A checksum mismatch is not a fallback case: it exits the setup.
cb_prebuilt_install() {
  local tool="$1" version="$2" mode="$3" dest="$4" name url tmp want got
  name="$(cb_prebuilt_asset "$tool" "$version" "$mode")" || {
    echo "ℹ️  No prebuilt ${tool} for CPU $(uname -m)"
    return 1
  }
  url="${CB_PREBUILT_URL}/${tool}-${version}/${name}.tar.gz"
  tmp="$(mktemp -d)"

  echo "⬇️  Downloading prebuilt ${name} ..."
  if ! curl --connect-timeout 15 --retry 3 --retry-delay 3 \
         -fsSL "$url" -o "$tmp/asset.tar.gz" \
     || ! curl --connect-timeout 15 --retry 3 --retry-delay 3 \
         -fsSL "${url}.sha256" -o "$tmp/asset.sha256"; then
    echo "ℹ️  No prebuilt asset at ${url}"
    rm -rf "$tmp"
    return 1
  fi

  want="$(awk '{print $1; exit}' "$tmp/asset.sha256")"
  got="$(sha256sum "$tmp/asset.tar.gz" | awk '{print $1}')"
  if [[ -z "$want" || "$want" != "$got" ]]; then
    echo "❌ ${name}.tar.gz: sha256 ${got} does not match the release's ${want:-<empty>}" >&2
    rm -rf "$tmp"
    exit 1
  fi

  "$(dirname "${BASH_SOURCE[0]}")/../cb-check-tar-extract.sh" || exit 1
  mkdir -p "$dest"
  tar -xzf "$tmp/asset.tar.gz" -C "$dest" --strip-components=1 --no-same-owner
  rm -rf "$tmp"
  echo "✅ Installed prebuilt ${name} into ${dest}"
}
