#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <sbt-version>|latest] [--user-home <path>] [--caches <dir>]

Examples:
  $0                               # install default (1.10.2)
  $0 --version latest              # install the latest sbt
  $0 --version 1.9.9               # install a specific version
  $0 --caches /opt/build-caches    # place all caches under a custom dir

Notes:
- Installs into /opt/sbt/sbt-<version> and links /opt/sbt-stable
- Adds /usr/local/bin/sbt wrapper so it works in non-login shells
- Uses shared caches (writable by all users) to speed up CI/dev
- Requires Java (JAVA_HOME should be set by your JDK setup)
USAGE
}

# ---- root check ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- defaults ----
SBT_DEFAULT_VERSION="1.10.2"     # bump when you want a newer pinned default
REQ_VERSION=""
USER_HOME_DEFAULT="/opt/sbt-user-home"   # not strictly used by sbt; convenient place for .sbt if you want
CACHES_ROOT_DEFAULT="/opt"               # caches live here by default

# ---- args ----
USER_HOME="$USER_HOME_DEFAULT"
CACHES_ROOT="$CACHES_ROOT_DEFAULT"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VERSION="${1:-}"; shift ;;
    --user-home) shift; USER_HOME="${1:-$USER_HOME_DEFAULT}"; shift ;;
    --caches) shift; CACHES_ROOT="${1:-$CACHES_ROOT_DEFAULT}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Resolve version (supports 'latest' via GitHub API)
if [[ -z "$REQ_VERSION" ]]; then
  VERSION="$SBT_DEFAULT_VERSION"
elif [[ "$REQ_VERSION" == "latest" ]]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/sbt/sbt/releases/latest | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
  [[ -n "$VERSION" ]] || { echo "❌ Failed to resolve latest sbt version"; exit 1; }
else
  VERSION="$REQ_VERSION"
fi

# ---- paths ----
INSTALL_PARENT=/opt/sbt
TARGET_DIR="${INSTALL_PARENT}/sbt-${VERSION}"
LINK_DIR=/opt/sbt-stable
BIN_WRAPPER=/usr/local/bin/sbt

# Shared caches (world-writable so any user/CI can reuse)
COURSIER_CACHE_DIR="${CACHES_ROOT}/coursier-cache"
IVY2_HOME_DIR="${CACHES_ROOT}/ivy2"
SBT_BOOT_DIR="${CACHES_ROOT}/sbt-boot"

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl unzip ca-certificates tar coreutils
rm -rf /var/lib/apt/lists/*

# ---- prepare dirs ----
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR" "$INSTALL_PARENT" "$USER_HOME" \
         "$COURSIER_CACHE_DIR" "$IVY2_HOME_DIR" "$SBT_BOOT_DIR"
chmod -R 0777 "$USER_HOME" "$COURSIER_CACHE_DIR_
