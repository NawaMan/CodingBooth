#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest sbt
  $0 --version 1.10.7        # pin specific version

Notes:
- Installs sbt to /opt/sbt and symlinks to /usr/local/bin/sbt
- Supports all architectures (sbt is JVM-based)
- Downloads from GitHub (sbt/sbt)
- Requires a JDK to be installed (e.g., setup jdk)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

PROFILE_FILE="/etc/profile.d/63-cb-sbt--profile.sh"

# ---- defaults / args ----
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- check JDK ----
if ! command -v java &>/dev/null; then
  echo "⚠️  Java not found on PATH. sbt requires a JDK to run."
  echo "   Install one first: e.g., setup jdk 21 temurin"
fi

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates jq
rm -rf /var/lib/apt/lists/*

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  echo "🔍 Resolving latest sbt version ..."
  VERSION="$(curl --retry 3 --retry-delay 2 -s https://api.github.com/repos/sbt/sbt/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
    echo "❌ Failed to resolve latest sbt version"; exit 1
  fi
  echo "   Latest version: ${VERSION}"
else
  if [[ ! "$REQ_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ --version must look like X.Y.Z (e.g., 1.10.7)"; exit 2
  fi
  VERSION="$REQ_VER"
fi

# ---- download and install ----
TARBALL_URL="https://github.com/sbt/sbt/releases/download/v${VERSION}/sbt-${VERSION}.tgz"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "⬇️  Downloading sbt ${VERSION} ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$TARBALL_URL" -o "$TMP/sbt.tgz"

echo "📦 Extracting to /opt/sbt ..."
rm -rf /opt/sbt
mkdir -p /opt/sbt
tar -xzf "$TMP/sbt.tgz" -C /opt/sbt --strip-components=1

# Sanity check
if [[ ! -x /opt/sbt/bin/sbt ]]; then
  echo "❌ Installation appears incomplete: /opt/sbt/bin/sbt not found" >&2
  exit 1
fi

# ---- symlink to /usr/local/bin ----
echo "🛠  Creating symlink in /usr/local/bin ..."
install -d /usr/local/bin
ln -sfn /opt/sbt/bin/sbt /usr/local/bin/sbt

# ---- profile script ----
cat >"${PROFILE_FILE}" <<'EOF'
# ---- sbt environment (safe to source multiple times) ----
export SBT_HOME=/opt/sbt
case ":$PATH:" in
  *":$SBT_HOME/bin:"*) : ;;
  *) export PATH="$SBT_HOME/bin:$PATH" ;;
esac
# ---- end sbt defaults ----
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- friendly summary ----
echo "✅ sbt ${VERSION} installed to /opt/sbt"
echo "   Binary:  /opt/sbt/bin/sbt"
echo "   Symlink: /usr/local/bin/sbt"
echo "   Profile: ${PROFILE_FILE}"

cat <<'EON'
ℹ️ Ready to use:
- Try: sbt --version
- Common commands:
    sbt new scala/scala3.g8   # create a new Scala 3 project
    sbt compile               # compile the project
    sbt test                  # run tests
    sbt run                   # run the application
    sbt assembly              # create a fat JAR

Notes:
- sbt requires a JDK. Make sure one is installed.
- First run may take a while as sbt downloads its dependencies.
EON
