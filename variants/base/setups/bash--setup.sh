#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.3.0

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
- The distro bash moves to /usr/bin/bash.distro. /usr/bin/bash becomes a
  dispatcher that runs it, or the bash named by CB_BASH when that is set.
  With CB_BASH unset nothing changes.
- Installs use-bash: \`use-bash 3.2 <cmd>\` sets CB_BASH, so every bash under
  <cmd> (#!/bin/bash, #!/usr/bin/env bash, bash -c) is that release.
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

# ---- dispatcher at /usr/bin/bash ----
# A shebang names a path, so PATH cannot send #!/bin/bash anywhere else. An
# environment variable reaches every process, whatever its shebang says. So
# /usr/bin/bash becomes a small dispatcher: it runs the distro bash, or the bash
# named by CB_BASH. use-bash sets CB_BASH. Nothing in the image sets it, so
# booth's own scripts and later build steps keep the distro bash.
#
# dpkg-divert keeps an apt upgrade of bash from overwriting the dispatcher; the
# upgrade lands on bash.distro instead. --no-rename plus a hard link, then one
# rename over the old path: /usr/bin/bash never goes missing, not even for
# this script's own children. A second `setup bash` (another release) finds
# the diversion in place and only rewrites the dispatcher.
DISTRO_BASH=/usr/bin/bash.distro
if [[ "$(dpkg-divert --truename /usr/bin/bash)" != "$DISTRO_BASH" ]]; then
  ln -f /usr/bin/bash "$DISTRO_BASH"
  dpkg-divert --local --no-rename --divert "$DISTRO_BASH" --add /usr/bin/bash
fi

# dash, not /bin/sh: if /bin/sh were ever pointed at bash, a #!/bin/sh
# dispatcher would run itself. A login shell needs argv[0] "-bash", which a
# script loses, so booth-entry logs coder in with bash.distro directly.
cat > /usr/bin/.bash.cb-dispatch <<'EOF'
#!/usr/bin/dash
# Installed by bash--setup.sh: runs the distro bash, or $CB_BASH when set.
# use-bash sets CB_BASH; it is inherited, so #!/bin/bash at any depth follows.
b="${CB_BASH:-}"
case "$b" in
  ""|/bin/bash|/usr/bin/bash) b=/usr/bin/bash.distro ;;
esac
case "$0" in
  *rbash) exec "$b" -r "$@" ;;
esac
exec "$b" "$@"
EOF
chmod 755 /usr/bin/.bash.cb-dispatch
mv -f /usr/bin/.bash.cb-dispatch /usr/bin/bash
command -v add-shell >/dev/null 2>&1 && add-shell "$DISTRO_BASH"

# ---- use-bash ----
cat > /usr/local/bin/use-bash <<'EOF'
#!/usr/bin/dash
# use-bash <bash> [command [args...]] -- installed by bash--setup.sh
set -eu

usage() {
  cat <<'USAGE'
Usage:
  use-bash <bash> [command [args...]]
  use-bash --list

<bash> is a release installed by `setup bash` (3.2, 3.2.57, 5.3), a path to
a bash binary, or "distro" for the image's own bash.

Every bash started under <command> is <bash>: #!/bin/bash, #!/usr/bin/env
bash and bash -c, at any depth. #!/bin/sh scripts stay on dash. With no
command, it opens an interactive shell; exit to leave it.

Examples:
  use-bash 3.2 ./script.sh one two
  use-bash 3.2 just test
  use-bash 3.2
  use-bash distro ./script.sh    # the image's bash, inside a 3.2 session
USAGE
}

version_of() { "$1" -c 'printf %s "$BASH_VERSION"' 2>/dev/null || true; }

list() {
  printf '%-8s %-20s %s\n' distro "$(version_of /usr/bin/bash.distro)" /usr/bin/bash.distro
  for b in /opt/bash/bash-*/bin/bash; do
    [ -x "$b" ] || continue
    v="$(version_of "$b")"
    printf '%-8s %-20s %s\n' "${v%%[!0-9.]*}" "$v" "$b"
  done
}

[ $# -gt 0 ] || { usage >&2; exit 2; }
case "$1" in
  -h|--help) usage; exit 0 ;;
  --list)    list;  exit 0 ;;
  distro)    target=/usr/bin/bash.distro ;;
  */*)       target="$1" ;;
  *)         target="/usr/local/bin/bash-$1" ;;
esac
if [ ! -x "$target" ]; then
  echo "use-bash: no bash '$1'. Installed:" >&2
  list >&2
  exit 2
fi
target="$(readlink -f "$target")"
# /usr/bin/bash is the dispatcher itself.
[ "$target" != /usr/bin/bash ] || target=/usr/bin/bash.distro
ver="$(version_of "$target")"
[ -n "$ver" ] || { echo "use-bash: $target is not a bash" >&2; exit 2; }
shift

CB_BASH="$target"
SHELL="$target"
export CB_BASH SHELL
if [ $# -eq 0 ]; then
  echo "use-bash: bash $ver for everything started here (exit to leave)" >&2
  exec "$target"
fi
exec "$@"
EOF
chmod 755 /usr/local/bin/use-bash

# ---- bash+default: the whole session ----
# bash+default makes a release here the login shell. This profile, read by
# that login shell, sets CB_BASH to it, so the session behaves as if started
# under use-bash. A login shell of the distro bash is left alone. (A docker -e
# CB_BASH would miss the session, which logs in with a clean environment, and
# would move booth-entry and every booth script onto the release instead.)
cat > /etc/profile.d/70-cb-bash--profile.sh <<'EOF'
# Installed by bash--setup.sh. See use-bash --help.
if [ -n "${BASH_VERSION:-}" ] && [ -z "${CB_BASH:-}" ]; then
  _cb_bash_exe="$(readlink /proc/$$/exe 2>/dev/null || true)"
  case "$_cb_bash_exe" in
    /opt/bash/*/bin/bash) CB_BASH="$_cb_bash_exe"; export CB_BASH ;;
  esac
  unset _cb_bash_exe
fi
EOF
chmod 644 /etc/profile.d/70-cb-bash--profile.sh

echo "✅ GNU Bash installed."
echo "   Version: ${VERSION} → ${TARGET_DIR}"
echo "   Command: bash-${MM}"
echo -n "   bash-${MM} --version → "
"${BIN_DIR}/bash-${MM}" --version | head -n1 || true

cat <<EON
ℹ️ Ready to use:
- bash-${MM} --version
- bash-${MM} ./script.sh        # this script only; children follow their shebang
- use-bash ${MM} ./script.sh    # every bash under it, #!/bin/bash included
- use-bash ${MM}                # an interactive shell where every bash is ${MM}

/bin/bash is still the image login shell. bash-${MM} is a second shell.
macOS ships Bash 3.2 as /bin/bash. Under set -u, "\${a[@]}" on an empty
array is an error there. \${a[@]+"\${a[@]}"} expands to nothing instead.
EON
