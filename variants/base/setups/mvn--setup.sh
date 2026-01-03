#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

PROFILE_FILE="/etc/profile.d/62-ws-maven--profile.sh"

MAVEN_VERSION=${1:-3.9.11}

# Optional override (e.g., corporate mirror): export MAVEN_MIRROR_BASE="https://my-mirror.example.com/maven"
PRIMARY_BASE="${MAVEN_MIRROR_BASE:-https://downloads.apache.org}/maven/maven-3"
ARCHIVE_BASE="https://archive.apache.org/dist/maven/maven-3"

INSTALL_PARENT=/opt/maven
TARGET_DIR="${INSTALL_PARENT}/maven-${MAVEN_VERSION}"
LINK_DIR=/opt/maven-stable

tarball="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
primary_url="${PRIMARY_BASE}/${MAVEN_VERSION}/binaries/${tarball}"
archive_url="${ARCHIVE_BASE}/${MAVEN_VERSION}/binaries/${tarball}"

# Pick a working URL (prefer primary, fall back to archive)
echo "Locating Apache Maven ${MAVEN_VERSION}..."
DOWNLOAD_URL="$primary_url"
if ! curl -fsIL "$DOWNLOAD_URL" >/dev/null 2>&1; then
  echo "Primary mirror does not have ${MAVEN_VERSION}; using archive."
  DOWNLOAD_URL="$archive_url"
fi

# --- Download tarball ---
echo "Downloading: $DOWNLOAD_URL"
curl -fsSL "$DOWNLOAD_URL" -o /tmp/maven.tar.gz

# --- Verify SHA-512 if available ---
sha_url="${DOWNLOAD_URL}.sha512"
if curl -fsSL "$sha_url" -o /tmp/maven.tar.gz.sha512 2>/dev/null; then
  echo "Verifying checksum..."
  expected="$(cut -d' ' -f1 /tmp/maven.tar.gz.sha512)"
  actual="$(sha512sum /tmp/maven.tar.gz | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    echo "❌ SHA-512 mismatch for Maven ${MAVEN_VERSION}" >&2
    exit 1
  fi
else
  echo "⚠️  No SHA-512 file found at ${sha_url}; skipping checksum verification."
fi
rm -f /tmp/maven.tar.gz.sha512 || true

# --- Install into /opt/maven/maven-<version> ---
rm    -rf  "$TARGET_DIR"
mkdir -p   "$TARGET_DIR"
tar   -xzf /tmp/maven.tar.gz -C "$TARGET_DIR" --strip-components=1
rm    -f   /tmp/maven.tar.gz

# --- Stable symlink directory for Maven ---
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# --- Make mvn available even in non-login shells ---
install -d /usr/local/bin
ln -sfn "$LINK_DIR/bin/mvn"      /usr/local/bin/mvn
ln -sfn "$LINK_DIR/bin/mvnDebug" /usr/local/bin/mvnDebug || true

# --- environment for login shells ---
cat >"${PROFILE_FILE}" <<'EOF'
# ---- container defaults (safe to source multiple times) ----
export MAVEN_HOME=/opt/maven-stable
export PATH="$MAVEN_HOME/bin:$PATH"
# ---- end defaults ----
EOF
chmod 0644 "${PROFILE_FILE}"

echo "✅ Maven ${MAVEN_VERSION} installed to ${TARGET_DIR} and linked at ${LINK_DIR}."
echo "   Try: mvn --version"
