#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y|X.Y.Z>]

Examples:
  $0                      # GNU Bash 3.2.57, installed as bash-3.2
  $0 --version 3.2.57     # same pin
  $0 --version 5.2.37     # installed as bash-5.2
  $0 --version 5.3        # installed as bash-5.3

Notes:
- 3.2.48 to 3.2.57 come prebuilt (static, sha256-checked) from
  https://github.com/NawaMan/Bash32Ubuntu/releases. Nothing is compiled.
- Any other release is built from https://ftp.gnu.org/gnu/bash/ (or a mirror)
- Installs under /opt/bash/bash-<version>
- Links /usr/local/bin/bash-<major>.<minor> (and bash-<version> when that differs)
- Leaves /bin/bash, the image login shell, alone
- Bash 3.2 is the shell macOS ships as /bin/bash. Under set -u, "\${a[@]}"
  on an empty array is an error there. \${a[@]+"\${a[@]}"} is not.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

# ---- defaults / args ----
# Do not read $BASH_VERSION here. That name is bash's own version string
# (the shell running this script). The requested release arrives as --version.
BASH_DEFAULT_VER="3.2.57"
REQ_VER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

VERSION="${REQ_VER:-$BASH_DEFAULT_VER}"
if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
  echo "❌ Not a bash version: '${VERSION}' (expected X.Y or X.Y.Z, as in 3.2.57 or 5.3)" >&2
  usage
  exit 2
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
MM="${MAJOR}.${MINOR}"

# GCC 15 (Ubuntu 26.04) defaults to C23. Bash 3.x is K&R C and needs gnu89
# plus -fpermissive. Bash before 5.3 needs gnu17. 5.3 compiles as C23.
CFLAGS_PIN=""
if (( MAJOR < 4 )); then
  CFLAGS_PIN="-std=gnu89 -fpermissive"
elif (( MAJOR < 5 || (MAJOR == 5 && MINOR < 3) )); then
  CFLAGS_PIN="-std=gnu17"
fi

INSTALL_PARENT=/opt/bash
TARGET_DIR="${INSTALL_PARENT}/bash-${VERSION}"
BIN_DIR=/usr/local/bin

mkdir -p /usr/local/src
TMP="$(mktemp -d /usr/local/src/bash-build.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Bash 3.2.48-3.2.57: a static build per patch level from
# NawaMan/Bash32Ubuntu, so the image needs no compiler. Each tarball has a
# .sha256 beside it; a mismatch stops the setup rather than installing it.
# Static, so the Ubuntu release in the asset name does not bind the image.
PREBUILT_REPO="https://github.com/NawaMan/Bash32Ubuntu/releases/download"
prebuilt_patch() {
  [[ "$VERSION" =~ ^3\.2\.([0-9]+)$ ]] || return 1
  (( 10#${BASH_REMATCH[1]} >= 48 && 10#${BASH_REMATCH[1]} <= 57 ))
}

install_prebuilt() {
  local arch
  case "$(uname -m)" in
    x86_64|amd64)  arch=x86_64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "❌ No prebuilt GNU Bash ${VERSION} for $(uname -m)" >&2; exit 1 ;;
  esac
  local name="bash-${VERSION}-ubuntu26.04-${arch}-static.tar.gz"
  local url="${PREBUILT_REPO}/bash-${VERSION}/${name}"

  if ! command -v curl >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends curl ca-certificates
    rm -rf /var/lib/apt/lists/*
  fi

  echo "⬇️  Downloading prebuilt GNU Bash ${VERSION} (${arch}) ..."
  curl --connect-timeout 15 --retry 3 --retry-delay 3 --retry-all-errors \
    -fsSL "$url" -o "$TMP/$name"
  curl --connect-timeout 15 --retry 3 --retry-delay 3 --retry-all-errors \
    -fsSL "${url}.sha256" -o "$TMP/${name}.sha256"
  local want got_sum
  want="$(awk '{print $1; exit}' "$TMP/${name}.sha256")"
  got_sum="$(sha256sum "$TMP/$name" | awk '{print $1}')"
  if [[ -z "$want" || "$want" != "$got_sum" ]]; then
    echo "❌ ${name}: sha256 ${got_sum} does not match the release's ${want:-<empty>}" >&2
    exit 1
  fi

  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  tar -xzf "$TMP/$name" -C "$TARGET_DIR" --strip-components=1
  [[ -x "$TARGET_DIR/bin/bash" ]] || { echo "❌ ${name} has no bin/bash" >&2; exit 1; }
}

build_from_source() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    build-essential bison libncurses-dev curl ca-certificates autotools-dev
  rm -rf /var/lib/apt/lists/*

  TARBALL="bash-${VERSION}.tar.gz"
  # Three sources, tried in order. --connect-timeout keeps an unreachable host
  # from costing minutes per retry before the next source gets its turn.
  MIRRORS=(
    "https://ftp.gnu.org/gnu/bash"
    "https://ftpmirror.gnu.org/bash"
    "https://mirrors.kernel.org/gnu/bash"
  )

  echo "⬇️  Downloading GNU Bash ${VERSION} ..."
  got_tarball=0
  for mirror in "${MIRRORS[@]}"; do
    if curl --connect-timeout 15 --retry 3 --retry-delay 3 --retry-all-errors \
        -fsSL "${mirror}/${TARBALL}" -o "$TMP/$TARBALL"; then
      got_tarball=1
      break
    fi
    echo "   ${mirror} failed, trying the next mirror..."
  done
  (( got_tarball )) || { echo "❌ Could not download ${TARBALL} from any mirror" >&2; exit 1; }

  echo "📦 Building GNU Bash ${VERSION} ..."
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"

  tar -xzf "$TMP/$TARBALL" -C "$TMP"
  SRC_DIR="$TMP/bash-${VERSION}"
  [[ -d "$SRC_DIR" ]] || { echo "❌ Expected source dir ${SRC_DIR}"; exit 1; }
  cd "$SRC_DIR"

  # The 3.2.57 tarball ships a y.tab.c from 2006. parse.y is newer and calls
  # expand_prompt_string with three arguments. bison (installed above) regenerates
  # the parser because parse.y is newer. Do not touch y.tab.c ahead of make.

  # A release cannot name a machine newer than itself. 3.2.57 ships
  # support/config.guess from 2002, which has never heard of aarch64, so on an
  # arm64 host — an Apple Silicon Mac, an arm64 runner — it gives up and configure
  # stops at "cannot guess build type" before a line is compiled. autotools-dev
  # (installed above) carries a current pair. Both are needed: config.sub is as old
  # and would reject the triplet config.guess now returns.
  #
  # Asking the shipped script is the whole test: it exits 0 and prints the triplet
  # when it knows the host, 1 and nothing when it does not. So a release new enough
  # to recognise the machine keeps its own, whatever the architecture.
  #
  # Through `sh`, not as a program: 3.2.57 ships config.guess executable and 5.3
  # does not, so running it directly answers 126 for the newer release and would
  # swap the files on every host. configure reaches them through $SHELL too, which
  # is why the missing bit costs 5.3 nothing.
  if ! sh support/config.guess >/dev/null 2>&1; then
    echo "   support/config.guess ($(uname -m)) is older than this architecture; using autotools-dev's"
    cp /usr/share/misc/config.guess /usr/share/misc/config.sub support/
  fi

  if [[ -n "$CFLAGS_PIN" ]]; then
    export CFLAGS="$CFLAGS_PIN"
    export CFLAGS_FOR_BUILD="$CFLAGS_PIN"
  fi

  ./configure --prefix="$TARGET_DIR" --without-bash-malloc

  # Bash 3.2 races under make -j: two jobs write support/newversion.h and one
  # mv fails. Build that line serially. Later releases take the core count.
  if (( MAJOR < 4 )); then
    make -j1
  else
    make -j"$(nproc)"
  fi
  make install
}

if prebuilt_patch; then
  install_prebuilt
else
  build_from_source
fi

ln -sfn "${TARGET_DIR}/bin/bash" "${BIN_DIR}/bash-${MM}"
if [[ "$VERSION" != "$MM" ]]; then
  ln -sfn "${TARGET_DIR}/bin/bash" "${BIN_DIR}/bash-${VERSION}"
fi

# BASH_VERSION here is the shell we just installed. It looks like
# 3.2.57(1)-release. Drop the release suffix before comparing.
got="$("${BIN_DIR}/bash-${MM}" -c 'printf %s "$BASH_VERSION"')"
got="${got%%\(*}"
case "$got" in
  "$VERSION"|"${VERSION}".*) ;;
  *) echo "❌ Installed bash reports ${got}, wanted ${VERSION}" >&2; exit 1 ;;
esac

echo "✅ GNU Bash installed."
echo "   Version: ${VERSION} → ${TARGET_DIR}"
echo "   Command: bash-${MM}"
echo -n "   bash-${MM} --version → "
"${BIN_DIR}/bash-${MM}" --version | head -n1 || true

cat <<EON
ℹ️ Ready to use:
- bash-${MM} --version
- bash-${MM} ./script.sh

/bin/bash is still the image login shell. bash-${MM} is a second shell.
macOS ships Bash 3.2 as /bin/bash. Under set -u, "\${a[@]}" on an empty
array is an error there. \${a[@]+"\${a[@]}"} expands to nothing instead.
EON
