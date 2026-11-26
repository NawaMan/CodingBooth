# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# ---- Prebuilt packages for the go/cargo/cabal install helpers ----
#
# go--install.sh, cargo--install.sh and cabal--install.sh install whatever a Boothfile
# names, so they compile by default. The packages the catalog itself installs (gopls and
# dlv in every Go booth, the protobuf plugins, ripgrep/fd/bat, hlint, ...) are built once
# by NawaMan/CodingBoothPrebuilt instead. These functions map a requested package to its
# prebuilt tool and resolve the version the package manager would have picked, so the
# helper can try cb_prebuilt_install first and compile only when there is no asset.
#
# Every lookup prints nothing and returns 1 when the package is not one of the known ones,
# or its version cannot be resolved (an @branch, a registry outage): the caller then
# compiles exactly as before, so a lookup can never make an install fail.
#
# Source with (prebuilt-source.sh is sourced too):
#   SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
#   source "${SETUP_LIBS_DIR}/prebuilt-packages.sh"
#
# The registries are overridable, which the tests use to stay offline:
#   CB_GO_PROXY_URL     (default https://proxy.golang.org)
#   CB_CRATES_API_URL   (default https://crates.io/api/v1/crates)
#   CB_HACKAGE_URL      (default https://hackage.haskell.org/package)

source "$(dirname "${BASH_SOURCE[0]}")/prebuilt-source.sh"

CB_GO_PROXY_URL="${CB_GO_PROXY_URL:-https://proxy.golang.org}"
CB_CRATES_API_URL="${CB_CRATES_API_URL:-https://crates.io/api/v1/crates}"
CB_HACKAGE_URL="${CB_HACKAGE_URL:-https://hackage.haskell.org/package}"

_cb_pkg_fetch() {
  curl --connect-timeout 15 --retry 3 --retry-delay 3 -fsSL "$@" 2>/dev/null
}

# cb_prebuilt_go <package@version>
#   Prints "<tool> <version> <executable>" for a Go command CodingBoothPrebuilt builds.
#   @latest is resolved through the module proxy (the version `go install` would get);
#   @vX.Y.Z is taken as is; anything else (no version, a branch, a pseudo-version) is not
#   prebuilt.
cb_prebuilt_go() {
  local spec="$1" path want tool module version
  path="${spec%@*}"
  [[ "$path" != "$spec" ]] || return 1
  want="${spec##*@}"
  case "$path" in
    golang.org/x/tools/gopls)                              tool=gopls;              module=golang.org/x/tools/gopls ;;
    golang.org/x/tools/cmd/goimports)                      tool=goimports;          module=golang.org/x/tools ;;
    github.com/go-delve/delve/cmd/dlv)                     tool=dlv;                module=github.com/go-delve/delve ;;
    google.golang.org/protobuf/cmd/protoc-gen-go)          tool=protoc-gen-go;      module=google.golang.org/protobuf ;;
    google.golang.org/grpc/cmd/protoc-gen-go-grpc)         tool=protoc-gen-go-grpc; module=google.golang.org/grpc/cmd/protoc-gen-go-grpc ;;
    github.com/golangci/golangci-lint/v2/cmd/golangci-lint) tool=golangci-lint;     module=github.com/golangci/golangci-lint/v2 ;;
    github.com/rakyll/hey)                                 tool=hey;                module=github.com/rakyll/hey ;;
    *) return 1 ;;
  esac
  if [[ "$want" == latest ]]; then
    version="$(_cb_pkg_fetch "${CB_GO_PROXY_URL}/${module}/@latest" \
               | sed -nE 's/.*"Version"[[:space:]]*:[[:space:]]*"v([^"]+)".*/\1/p')"
  else
    version="${want#v}"
  fi
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  echo "$tool $version ${path##*/}"
}

# cb_prebuilt_crate <crate[@version]>
#   Prints "<tool> <version> <executable>..." for a crate CodingBoothPrebuilt builds. No
#   version means crates.io's newest stable one (what `cargo install` would get).
cb_prebuilt_crate() {
  local spec="$1" crate version bins
  crate="${spec%@*}"
  case "$crate" in
    ripgrep) bins=rg ;;
    fd-find) bins=fd ;;
    bat)     bins=bat ;;
    *) return 1 ;;
  esac
  if [[ "$crate" == "$spec" ]]; then
    version="$(_cb_pkg_fetch -A "CodingBooth (https://github.com/NawaMan/CodingBooth)" \
                 "${CB_CRATES_API_URL}/${crate}" \
               | sed -nE 's/.*"max_stable_version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
  else
    version="${spec##*@}"
    version="${version#=}"
  fi
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  echo "$crate $version $bins"
}

# cb_prebuilt_cabal <package[-version]|package==version>
#   Prints "<tool> <version>" for a Hackage package CodingBoothPrebuilt builds. No version
#   means Hackage's newest preferred one.
cb_prebuilt_cabal() {
  local spec="$1" pkg version
  if [[ "$spec" =~ ^([a-z][a-z0-9-]*[a-z])(-|==)([0-9][0-9.]*)$ ]]; then
    pkg="${BASH_REMATCH[1]}" version="${BASH_REMATCH[3]}"
  else
    pkg="$spec" version=""
  fi
  case "$pkg" in
    hlint|ormolu) ;;
    *) return 1 ;;
  esac
  if [[ -z "$version" ]]; then
    version="$(_cb_pkg_fetch -H 'Accept: application/json' "${CB_HACKAGE_URL}/${pkg}/preferred" \
               | sed -nE 's/.*"normal-version"[[:space:]]*:[[:space:]]*\[[[:space:]]*"([^"]+)".*/\1/p')"
  fi
  [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  echo "$pkg $version"
}
