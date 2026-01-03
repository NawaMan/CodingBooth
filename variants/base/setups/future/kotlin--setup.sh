#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <x.y.z>|latest] [--with-native] [--konan-dir </path>] [--with-kls]

Examples:
  $0                         # Kotlin compiler (JVM/JS) default 2.0.20
  $0 --version latest        # latest Kotlin
  $0 --version 2.0.10 --with-native                  # add Kotlin/Native
  $0 --with-native --konan-dir /opt/konan            # shared konan cache
  $0 --with-kls             # install Kotlin Language Server (kls)

Notes:
- JVM/JS compiler extracted to /opt/kotlin/kotlin-<ver> -> /opt/kotlin-stable
- (Optional) Kotlin/Native to /opt/kotlin-native/kotlin-native-<ver> -> /opt/kotlin-native-stable
- /usr/local/bin symlinks & wrapper ensure tools work in non-login shells
- Requires Java (JAVA_HOME) for JVM/JS compiler
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# ---- defaults / args ----
KOTLIN_DEFAULT_VER="2.0.20"     # update when you want a newer pinned default
REQ_VER=""
WITH_NATIVE=0
WITH_KLS=0
KONAN_DIR_DEFAULT="/opt/konan"
KONAN_DIR="$KONAN_DIR_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)     shift; REQ_VER="${1:-}"; shift ;;
    --with-native) WITH_NATIVE=1; shift ;;
    --konan-dir)   shift; KONAN_DIR="${1:-$KONAN_DIR_DEFAULT}"; shift ;;
    --with-kls)    WITH_KLS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Resolve version (supports 'latest' via GitHub API)
if [[ -z "$REQ_VER" ]]; then
  KVER="$KOTLIN_DEFAULT_VER"
elif [[ "$REQ_VER" == "latest" ]]; then
  KVER="$(curl -fsSL https://api.github.com/repos/JetBrains/kotlin/releases/latest | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
  [[ -n "$KVER" ]] || { echo "❌ Failed to resolve latest Kotlin version"; exit 1; }
else
  KVER="$REQ_VER"
fi

# ---- arch detection for Kotlin/Native ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  KN_ARCH="x86_64";;
  arm64)  KN_ARCH="aarch64";;
  *) if [[ $WITH_NATIVE -eq 1 ]]; then echo "❌ Kotlin/Native unsupported arch: $dpkgArch"; exit 1; fi ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends coreutils
rm -rf /var/lib/apt/lists/*

# ---- locations ----
INSTALL_PARENT=/opt/kotlin
KOTLIN_DIR="${INSTALL_PARENT}/kotlin-${KVER}"
KOTLIN_LINK=/opt/kotlin-stable

KN_PARENT=/opt/kotlin-native
KN_DIR="${KN_PARENT}/kotlin-native-${KVER}"
KN_LINK=/opt/kotlin-native-stable

BIN_DIR=/usr/local/bin

# Clean old shims (idempotent)
for b in kotlin kotlinc kotlinc-jvm kotlinc-js kotlinc-native konanc klib kdoctor kls; do
  rm -f "${BIN_DIR}/$b" || true
done

# ---- JVM/JS compiler install ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
K_ZIP_URL="https://github.com/JetBrains/kotlin/releases/download/v${KVER}/kotlin-compiler-${KVER}.zip"

echo "⬇️  Downloading Kotlin compiler ${KVER} ..."
curl -fsSL "$K_ZIP_URL" -o "$TMP/kotlin.zip"

echo "📦 Installing Kotlin compiler ${KVER} ..."
rm -rf "$KOTLIN_DIR"
mkdir -p "$KOTLIN_DIR"
unzip -q "$TMP/kotlin.zip" -d "$TMP"      # extracts kotlin/
mv "$TMP/kotlin"/* "$KOTLIN_DIR"

# Stable link
ln -sfn "$KOTLIN_DIR" "$KOTLIN_LINK"

# ---- Kotlin/Native (optional) ----
if [[ $WITH_NATIVE -eq 1 ]]; then
  # Kotlin/Native tarball name pattern:
  #   kotlin-native-linux-<arch>-<ver>.tar.gz
  KN_TGZ_URL="https://github.com/JetBrains/kotlin/releases/download/v${KVER}/kotlin-native-linux-${KN_ARCH}-${KVER}.tar.gz"
  echo "⬇️  Downloading Kotlin/Native ${KVER} (${KN_ARCH}) ..."
  curl -fsSL "$KN_TGZ_URL" -o "$TMP/konan.tgz"

  echo "📦 Installing Kotlin/Native ${KVER} ..."
  rm -rf "$KN_DIR"
  mkdir -p "$KN_DIR"
  tar -xzf "$TMP/konan.tgz" -C "$TMP"     # extracts kotlin-native-<ver>/
  # Find extracted folder (JetBrains varies slightly)
  KN_EXTRACT_DIR="$(find "$TMP" -maxdepth 1 -type d -name "kotlin-native-*" | head -n1)"
  [[ -d "$KN_EXTRACT_DIR" ]] || { echo "❌ Could not find extracted Kotlin/Native directory"; exit 1; }
  mv "$KN
