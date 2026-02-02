#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <x.y.z>|latest] [--with-native] [--konan-dir </path>]

Examples:
  $0                         # Kotlin compiler (JVM/JS) default 2.0.20
  $0 --version latest        # latest Kotlin
  $0 --version 2.0.10 --with-native  # add Kotlin/Native

Notes:
- JVM/JS compiler extracted to /opt/kotlin/kotlin-<ver> -> /opt/kotlin-stable
- (Optional) Kotlin/Native to /opt/kotlin-native/kotlin-native-<ver> -> /opt/kotlin-native-stable
- /usr/local/bin symlinks ensure tools work in non-login shells
- Requires Java (JAVA_HOME) for JVM/JS compiler
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "Run as root (use sudo)"; exit 1; }

# ---- defaults / args ----
KOTLIN_DEFAULT_VER="2.0.20"
REQ_VER=""
WITH_NATIVE=0
KONAN_DIR_DEFAULT="/opt/konan"
KONAN_DIR="$KONAN_DIR_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)     shift; REQ_VER="${1:-}"; shift ;;
    --with-native) WITH_NATIVE=1; shift ;;
    --konan-dir)   shift; KONAN_DIR="${1:-$KONAN_DIR_DEFAULT}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Resolve version (supports 'latest' via GitHub API)
if [[ -z "$REQ_VER" ]]; then
  KVER="$KOTLIN_DEFAULT_VER"
elif [[ "$REQ_VER" == "latest" ]]; then
  KVER="$(curl -fsSL https://api.github.com/repos/JetBrains/kotlin/releases/latest | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
  [[ -n "$KVER" ]] || { echo "Failed to resolve latest Kotlin version"; exit 1; }
else
  KVER="$REQ_VER"
fi

# ---- arch detection for Kotlin/Native ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64)  KN_ARCH="x86_64";;
  arm64)  KN_ARCH="aarch64";;
  *) if [[ $WITH_NATIVE -eq 1 ]]; then echo "Kotlin/Native unsupported arch: $dpkgArch"; exit 1; fi ;;
esac

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates unzip coreutils
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
for b in kotlin kotlinc kotlinc-jvm kotlinc-js kotlinc-native konanc klib; do
  rm -f "${BIN_DIR}/$b" || true
done

# ---- JVM/JS compiler install ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
K_ZIP_URL="https://github.com/JetBrains/kotlin/releases/download/v${KVER}/kotlin-compiler-${KVER}.zip"

echo "Downloading Kotlin compiler ${KVER} ..."
curl -fsSL "$K_ZIP_URL" -o "$TMP/kotlin.zip"

echo "Installing Kotlin compiler ${KVER} ..."
rm -rf "$KOTLIN_DIR"
mkdir -p "$KOTLIN_DIR"
unzip -q "$TMP/kotlin.zip" -d "$TMP"
mv "$TMP/kotlinc"/* "$KOTLIN_DIR" 2>/dev/null || mv "$TMP/kotlin"/* "$KOTLIN_DIR"

# Stable link
ln -sfn "$KOTLIN_DIR" "$KOTLIN_LINK"

# ---- Kotlin/Native (optional) ----
if [[ $WITH_NATIVE -eq 1 ]]; then
  KN_TGZ_URL="https://github.com/JetBrains/kotlin/releases/download/v${KVER}/kotlin-native-linux-${KN_ARCH}-${KVER}.tar.gz"
  echo "Downloading Kotlin/Native ${KVER} (${KN_ARCH}) ..."
  curl -fsSL "$KN_TGZ_URL" -o "$TMP/konan.tgz"

  echo "Installing Kotlin/Native ${KVER} ..."
  rm -rf "$KN_DIR"
  mkdir -p "$KN_DIR"
  tar -xzf "$TMP/konan.tgz" -C "$TMP"
  KN_EXTRACT_DIR="$(find "$TMP" -maxdepth 1 -type d -name "kotlin-native-*" | head -n1)"
  [[ -d "$KN_EXTRACT_DIR" ]] || { echo "Could not find extracted Kotlin/Native directory"; exit 1; }
  mv "$KN_EXTRACT_DIR"/* "$KN_DIR"

  # Stable link for native
  ln -sfn "$KN_DIR" "$KN_LINK"

  # Konan cache directory
  mkdir -p "$KONAN_DIR"
  chmod 0777 "$KONAN_DIR"
fi

# ---- login-shell env ----
cat >/etc/profile.d/61-cb-kotlin--profile.sh <<'EOF'
# Kotlin under /opt
export KOTLIN_HOME=/opt/kotlin-stable
export PATH="$KOTLIN_HOME/bin:$PATH"
# Kotlin/Native (if installed)
if [ -d /opt/kotlin-native-stable/bin ]; then
  export KOTLIN_NATIVE_HOME=/opt/kotlin-native-stable
  export PATH="$KOTLIN_NATIVE_HOME/bin:$PATH"
  export KONAN_DATA_DIR="${KONAN_DATA_DIR:-/opt/konan}"
fi
EOF
chmod 0644 /etc/profile.d/61-cb-kotlin--profile.sh

# ---- non-login wrappers ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/kotlinwrap" <<'EOF'
#!/bin/sh
: "${KOTLIN_HOME:=/opt/kotlin-stable}"
: "${KOTLIN_NATIVE_HOME:=/opt/kotlin-native-stable}"
export PATH="$KOTLIN_HOME/bin:$KOTLIN_NATIVE_HOME/bin:$PATH"
tool="$(basename "$0")"
if [ -x "$KOTLIN_HOME/bin/$tool" ]; then
  exec "$KOTLIN_HOME/bin/$tool" "$@"
elif [ -x "$KOTLIN_NATIVE_HOME/bin/$tool" ]; then
  exec "$KOTLIN_NATIVE_HOME/bin/$tool" "$@"
else
  exec "$(command -v "$tool")" "$@"
fi
EOF
chmod +x "${BIN_DIR}/kotlinwrap"

for t in kotlin kotlinc kotlinc-jvm kotlinc-js; do
  ln -sfn "${BIN_DIR}/kotlinwrap" "${BIN_DIR}/$t"
done

if [[ $WITH_NATIVE -eq 1 ]]; then
  for t in kotlinc-native konanc klib; do
    ln -sfn "${BIN_DIR}/kotlinwrap" "${BIN_DIR}/$t"
  done
fi

# ---- summary ----
echo "Kotlin ${KVER} installed at ${KOTLIN_DIR} (linked at ${KOTLIN_LINK})."
echo -n "   kotlinc: "; "${BIN_DIR}/kotlinc" -version 2>&1 | head -n1 || true
if [[ $WITH_NATIVE -eq 1 ]]; then
  echo "   Kotlin/Native installed at ${KN_DIR} (linked at ${KN_LINK})."
fi

cat <<'EON'
Ready to use:
- Try: kotlinc -version
- Requires JAVA_HOME set (use jdk--setup.sh first)
- Kotlin/Native (if installed): kotlinc-native -version
EON
