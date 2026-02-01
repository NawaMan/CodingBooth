#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--scala-version <3.x.y>] [--with-ammonite|--no-ammonite]

Examples:
  $0                                  # default Scala 3.5.1 + coursier + scala-cli
  $0 --scala-version 3.4.2            # pin a specific Scala 3 version
  $0 --with-ammonite                  # also install Ammonite (via coursier)

Notes:
- Installs Scala into /opt/scala/scala-<version>, links /opt/scala-stable
- Installs Coursier (cs) + Scala CLI; exposes tools via /usr/local/bin
- Requires Java (JAVA_HOME should be set by your JDK script)
USAGE
}

# --- root check ---
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- defaults / args ---
SCALA_DEFAULT="3.5.1"
SCALA_VER="$SCALA_DEFAULT"
WITH_AMM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scala-version) shift; SCALA_VER="${1:-$SCALA_DEFAULT}"; shift ;;
    --with-ammonite) WITH_AMM=1; shift ;;
    --no-ammonite)   WITH_AMM=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# --- arch guard ---
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) CS_ARCH="x86_64";  ;;
  arm64) CS_ARCH="aarch64"; ;;
  *) echo "❌ Unsupported arch: $dpkgArch (supported: amd64, arm64)"; exit 1 ;;
esac

# --- base deps ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates zip unzip coreutils
rm -rf /var/lib/apt/lists/*

# --- locations ---
INSTALL_PARENT=/opt/scala
SCALA_DIR="${INSTALL_PARENT}/scala-${SCALA_VER}"
LINK_DIR=/opt/scala-stable
BIN_DIR=/usr/local/bin

# --- clean old shims (idempotent) ---
for b in scala scalac scaladoc scala-cli cs amm ammonite; do
  rm -f "${BIN_DIR}/$b" || true
done

# --- install Scala 3 distribution (scala + scalac) ---
# Official tarballs from lampepfl/dotty releases follow this pattern:
#   https://github.com/lampepfl/dotty/releases/download/<ver>/scala3-<ver>.tar.gz
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SCALA_TGZ_URL="https://github.com/lampepfl/dotty/releases/download/${SCALA_VER}/scala3-${SCALA_VER}.tar.gz"

echo "⬇️  Downloading Scala ${SCALA_VER} ..."
curl -fsSL "$SCALA_TGZ_URL" -o "$TMP/scala.tgz"

echo "📦 Installing Scala ${SCALA_VER} ..."
rm -rf "$SCALA_DIR"
mkdir -p "$SCALA_DIR"
tar -xzf "$TMP/scala.tgz" -C "$TMP"
# extracted folder: scala3-<ver>
mv "$TMP/scala3-${SCALA_VER}"/* "$SCALA_DIR"

# --- stable link ---
ln -sfn "$SCALA_DIR" "$LINK_DIR"

# --- install Coursier (cs) ---
# Official static launcher
CS_URL="https://github.com/coursier/launchers/raw/master/cs-${CS_ARCH}-pc-linux.gz"
echo "⬇️  Installing Coursier launcher ..."
curl -fsSL "$CS_URL" -o "$TMP/cs.gz"
gunzip -f "$TMP/cs.gz"
install -Dm755 "$TMP/cs" "${BIN_DIR}/cs"

# --- use cs to install Scala CLI (+ optional Ammonite) into /opt/scala/bin ---
TOOLS_HOME="/opt/scala/tools"
mkdir -p "$TOOLS_HOME/bin"
chmod -R 0777 "$TOOLS_HOME" || true

# Ensure cs respects our install dir & PATH
export COURSIER_BIN_DIR="$TOOLS_HOME/bin"
export PATH="$COURSIER_BIN_DIR:$PATH"

# Install scala-cli (latest) and optionally Ammonite
cs install --only-prebuilt scala-cli
if [[ $WITH_AMM -eq 1 ]]; then
  cs install --only-prebuilt ammonite
fi

# Symlink primary tools to /usr/local/bin (non-login shells)
ln -sfn "$LINK_DIR/bin/scala"   "${BIN_DIR}/scala"
ln -sfn "$LINK_DIR/bin/scalac"  "${BIN_DIR}/scalac"
ln -sfn "$LINK_DIR/bin/scaladoc" "${BIN_DIR}/scaladoc" || true
ln -sfn "$COURSIER_BIN_DIR/scala-cli" "${BIN_DIR}/scala-cli" || true
if [[ -x "$COURSIER_BIN_DIR/amm" ]]; then
  ln -sfn "$COURSIER_BIN_DIR/amm" "${BIN_DIR}/amm"
  ln -sfn "$COURSIER_BIN_DIR/amm" "${BIN_DIR}/ammonite"
fi

# --- login-shell env (PATH) ---
cat >/etc/profile.d/99-scala--profile.sh <<'EOF'
# Scala defaults under /opt
export SCALA_HOME=/opt/scala-stable
export PATH="$SCALA_HOME/bin:/opt/scala/tools/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/99-scala--profile.sh

# --- fish / nushell convenience (optional but nice) ---
install -d /etc/fish/conf.d
cat >/etc/fish/conf.d/scala.fish <<'EOF'
set -gx SCALA_HOME /opt/scala-stable
fish_add_path -g /opt/scala/tools/bin $SCALA_HOME/bin
EOF
chmod 0644 /etc/fish/conf.d/scala.fish

install -d /etc/nu
cat >/etc/nu/scala.nu <<'EOF'
$env.SCALA_HOME = "/opt/scala-stable"
$env.PATH = ("/opt/scala/tools/bin" | path add $env.PATH)
$env.PATH = ($env.SCALA_HOME | path join "bin" | path add $env.PATH)
EOF
chmod 0644 /etc/nu/scala.nu

# --- summary ---
echo "✅ Scala ${SCALA_VER} installed at ${SCALA_DIR} (linked at ${LINK_DIR})."
echo -n "   scala:      "; "${BIN_DIR}/scala" -version 2>&1 | head -n1 || true
echo -n "   scalac:     "; "${BIN_DIR}/scalac" -version 2>&1 | head -n1 || true
echo -n "   scala-cli:  "; "${BIN_DIR}/scala-cli" version 2>/dev/null || true
if command -v "${BIN_DIR}/amm" >/dev/null 2>&1; then
  echo -n "   ammonite:   "; "${BIN_DIR}/amm" --version 2>/dev/null || true
fi

cat <<'EON'
ℹ️ Ready to use:
- Try: scala -version && scalac -version
- Scala CLI: scala-cli run Hello.scala    # compiles/runs with your JDK
- Ammonite REPL (if installed): amm

Notes:
- JAVA_HOME should already be set by your JDK setup.
- To switch Scala versions later, re-run with --scala-version <3.x.y> (updates /opt/scala-stable).
EON
