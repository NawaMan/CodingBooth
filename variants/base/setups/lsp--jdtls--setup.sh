#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

# lsp--jdtls--setup.sh — Install jdtls, the Eclipse JDT language server for Java.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                       # latest jdtls milestone
  $0 --version 1.63.0      # pin a milestone

Notes:
- Installs the milestone build from download.eclipse.org under /opt/jdtls
- Checks the download against the .sha256 published beside it
- Installs /usr/local/bin/jdtls, a bash launcher (the upstream one needs Python)
- Runs on Java 21 or newer: select the java template
- Per-project index data goes to ~/.cache/jdtls/
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

JDTLS_FALLBACK_VER="1.63.0"
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

BASE="https://download.eclipse.org/jdtls/milestones"
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl -fsSL --retry 3 --retry-delay 2 "${BASE}/" 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1 || true)
  if [[ -z "$VERSION" ]] || ! [[ "$VERSION" =~ $VERSION_RE ]]; then
    echo "⚠️  Could not resolve the latest jdtls milestone; using ${JDTLS_FALLBACK_VER}."
    VERSION="$JDTLS_FALLBACK_VER"
  fi
else
  VERSION="${REQ_VER#v}"
fi
if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "❌ Not a jdtls version: '${VERSION}' (expected X.Y.Z, for example 1.63.0)" >&2
  exit 2
fi

# Each milestone directory names its one build (with a timestamp) in latest.txt.
TARBALL=$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors "${BASE}/${VERSION}/latest.txt" | tr -d '[:space:]')
if [[ ! "$TARBALL" =~ ^jdt-language-server-.*\.tar\.gz$ ]]; then
  echo "❌ No jdtls build listed for ${VERSION} (${BASE}/${VERSION}/latest.txt)" >&2
  exit 1
fi

echo "⬇️  Installing jdtls ${VERSION} (${TARBALL}) ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE}/${VERSION}/${TARBALL}" -o "$TMP/jdtls.tar.gz"
if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE}/${VERSION}/${TARBALL}.sha256" -o "$TMP/jdtls.sha256"; then
  echo "❌ No .sha256 published for ${TARBALL}; refusing to install unverified bytes." >&2
  exit 1
fi
EXPECTED="$(awk 'NF { print $1; exit }' "$TMP/jdtls.sha256" | tr -d '[:space:]')"
ACTUAL="$(sha256sum "$TMP/jdtls.tar.gz" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "❌ SHA256 mismatch for ${TARBALL} (expected '${EXPECTED}', got '${ACTUAL}')" >&2
  exit 1
fi

rm -rf /opt/jdtls
mkdir -p /opt/jdtls
tar -xzf "$TMP/jdtls.tar.gz" -C /opt/jdtls
chmod -R a+rX /opt/jdtls

# The upstream bin/jdtls is a Python script, and the base image has no Python.
# This is the same launch: shared read-only config, per-project -data directory.
cat > /usr/local/bin/jdtls <<'LAUNCH'
#!/bin/bash
# Installed by lsp--jdtls--setup.sh: starts the Eclipse JDT language server.
set -euo pipefail
JDTLS_HOME=/opt/jdtls
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
command -v "$JAVA" >/dev/null 2>&1 || { echo "jdtls: no java on PATH (select the java template)" >&2; exit 1; }
major=$("$JAVA" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -1)
if [[ -n "$major" && "$major" -lt 21 ]]; then
  echo "jdtls: needs Java 21 or newer, found ${major}" >&2
  exit 1
fi
case "$(uname -m)" in
  aarch64|arm64) config="$JDTLS_HOME/config_linux_arm" ;;
  *)             config="$JDTLS_HOME/config_linux" ;;
esac
launcher=$(ls "$JDTLS_HOME"/plugins/org.eclipse.equinox.launcher_*.jar | head -1)
data="${XDG_CACHE_HOME:-$HOME/.cache}/jdtls/$(pwd | sha1sum | cut -c1-16)"
extra=()
[[ -n "$major" && "$major" -ge 24 ]] && extra=(-Djdk.xml.maxGeneralEntitySizeLimit=0 -Djdk.xml.totalEntitySizeLimit=0)
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -data) data="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
exec "$JAVA" "${extra[@]}" \
  -Declipse.application=org.eclipse.jdt.ls.core.id1 \
  -Dosgi.bundles.defaultStartLevel=4 \
  -Declipse.product=org.eclipse.jdt.ls.core.product \
  -Dosgi.checkConfiguration=true \
  -Dosgi.sharedConfiguration.area="$config" \
  -Dosgi.sharedConfiguration.area.readOnly=true \
  -Dosgi.configuration.cascaded=true \
  -Xms1G \
  --add-modules=ALL-SYSTEM \
  --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  -jar "$launcher" -data "$data" "${args[@]}"
LAUNCH
chmod 755 /usr/local/bin/jdtls

echo "✅ jdtls installed."
echo "   jdtls → /opt/jdtls (${TARBALL})"
command -v java >/dev/null 2>&1 || echo "⚠️  No java on PATH yet: jdtls needs Java 21 or newer (select the java template)."

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: jdtls
- Fresh, Helix, and neovim+lsp pick it up for Java files (Maven, Gradle, or plain sources)

Notes:
- The first open of a project indexes it, which takes a while; the index lives in ~/.cache/jdtls/.
- See: https://github.com/eclipse-jdtls/eclipse.jdt.ls
EON
