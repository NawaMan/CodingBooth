#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO: $BASH_COMMAND" >&2' ERR

# --- Config ---
IDE="${1:-}"              # e.g., pycharm, idea, goland, webstorm
VER="${2:-2025.2.3}"

# ===================== Show supported IDEs =====================
if [[ "$IDE" == "--list" ]]; then
  cat <<'EOF'
Supported JetBrains IDEs:

  COMMUNITY (Open Source, Apache 2.0 — freely redistributable)
  ─────────────────────────────────────────────────────────────
  idea       → IntelliJ IDEA Community Edition
  pycharm    → PyCharm Community Edition

  COMMERCIAL (Proprietary — license required; redistribution forbidden)
  ─────────────────────────────────────────────────────────────
  goland     → GoLand
  webstorm   → WebStorm
  phpstorm   → PhpStorm
  clion      → CLion
  rider      → Rider
  rubymine   → RubyMine
  datagrip   → DataGrip

Usage examples:
  sudo ./jetbrains--setup.sh pycharm
  sudo ./jetbrains--setup.sh idea 2025.2.3
  sudo ./jetbrains--setup.sh goland 2025.2.3

─────────────────────────────────────────────────────────────
⚠️  IMPORTANT LICENSE NOTICE
─────────────────────────────────────────────────────────────
• This script only automates **download and installation**.
  It never includes or redistributes JetBrains binaries.

• Community editions (IntelliJ IDEA CE, PyCharm CE) are
  licensed under the Apache 2.0 license and may be freely
  redistributed, repackaged, or preinstalled.

• All other JetBrains IDEs (GoLand, WebStorm, Rider, etc.)
  are **commercial products**. Redistribution of their binaries
  — even without license keys — is **strictly prohibited** by
  the JetBrains EULA.

─────────────────────────────────────────────────────────────
🚫 Actions that COUNT as redistribution (NOT ALLOWED)
─────────────────────────────────────────────────────────────
✗ Publishing a Docker image with a JetBrains IDE already installed  
✗ Uploading preinstalled IDE binaries to GitHub, GCS, S3, etc.  
✗ Sharing a VM, VDI, or ISO snapshot that includes JetBrains IDEs  
✗ Embedding JetBrains IDEs inside another software product  
✗ Making prebuilt container images publicly accessible  

─────────────────────────────────────────────────────────────
✅ Allowed actions (SAFE)
─────────────────────────────────────────────────────────────
✔ Sharing this script or a Dockerfile that downloads from
  JetBrains servers at build or runtime  
✔ Using the IDE in your own Docker container privately  
✔ Hosting internal builds only if all users have valid licenses  
✔ Distributing Community Edition builds (Apache 2.0 license)  

─────────────────────────────────────────────────────────────
Summary:
  Community editions → freely redistributable
  Commercial IDEs    → user must install & license themselves
─────────────────────────────────────────────────────────────
EOF
  exit 0
fi

# --- Ensure root ---
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "Must be root"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    echo "SKIP: $SCRIPT_NAME - desktop environment not available" >&2
    exit 42
fi

# --- Load booth JDK/Python env if available ---
source /etc/profile.d/60-cb-jdk--profile.sh    2>/dev/null || true
source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64)  ARCH_SUFFIX="" ;;
  aarch64|arm64) ARCH_SUFFIX="-aarch64" ;;
  *) echo "⚠️ Unrecognized arch '$ARCH_RAW'; using generic"; ARCH_SUFFIX="";;
esac

# --- Map IDE to base URL, tarball pattern, product code ---
case "$IDE" in
  pycharm)
    PRODUCT="PyCharm Community"
    BASE="https://download-cdn.jetbrains.com/python"
    TARBALL="pycharm-community-${VER}${ARCH_SUFFIX}.tar.gz"
    INSTALL_DIR="/opt/pycharm-PC-${VER}"
    ;;
  idea)
    PRODUCT="IntelliJ IDEA Community"
    BASE="https://download-cdn.jetbrains.com/idea"
    TARBALL="ideaIC-${VER}${ARCH_SUFFIX}.tar.gz"
    INSTALL_DIR="/opt/idea-IC-${VER}"
    ;;
  goland)
    PRODUCT="GoLand"
    BASE="https://download-cdn.jetbrains.com/go"
    TARBALL="goland-${VER}${ARCH_SUFFIX}.tar.gz"
    INSTALL_DIR="/opt/goland-${VER}"
    ;;
  webstorm)
    PRODUCT="WebStorm"
    BASE="https://download-cdn.jetbrains.com/webstorm"
    TARBALL="WebStorm-${VER}${ARCH_SUFFIX}.tar.gz"
    INSTALL_DIR="/opt/webstorm-${VER}"
    ;;
  phpstorm)
    PRODUCT="PhpStorm"
    BASE="https://download-cdn.jetbrains.com/webide"
    TARBALL="PhpStorm-${VER}${ARCH_SUFFIX}.tar.gz"
    INSTALL_DIR="/opt/phpstorm-${VER}"
    ;;
  clion)
    PRODUCT="CLion"
    BASE="https://download-cdn.jetbrains.com/cpp"
    TARBALL="CLion-${VER}${ARCH_SUFFIX}.tar.gz"
    INSTALL_DIR="/opt/clion-${VER}"
    ;;
  rider)
    PRODUCT="Rider"
    BASE="https://download-cdn.jetbrains.com/rider"
    TARBALL="JetBrains.Rider-${VER}.tar.gz"
    INSTALL_DIR="/opt/rider-${VER}"
    ;;
  rubymine)
    PRODUCT="RubyMine"
    BASE="https://download-cdn.jetbrains.com/ruby"
    TARBALL="RubyMine-${VER}${ARCH_SUFFIX}.tar.gz"
    INSTALL_DIR="/opt/rubymine-${VER}"
    ;;
  datagrip)
    PRODUCT="DataGrip"
    BASE="https://download-cdn.jetbrains.com/datagrip"
    TARBALL="datagrip-${VER}.tar.gz"
    INSTALL_DIR="/opt/datagrip-${VER}"
    ;;
  *)
    echo "❌ Unsupported IDE name: $IDE"
    exit 1
    ;;
esac


PROFILE_FILE="/etc/profile.d/70-cb-${IDE}--profile.sh"
STARTER_FILE="${INSTALL_DIR}/${IDE}-starter"


LINK_DIR="/opt/${IDE}"
SHIM_BIN="/usr/local/bin/${IDE}"
DESKTOP_FILE="/usr/share/applications/${IDE}-${VER}.desktop"

URL="${BASE}/${TARBALL}"
SHA_URL="${URL}.sha256"

echo "• Installing $PRODUCT ${VER} (${ARCH_RAW})"
echo "• From: ${URL}"
echo "• To:   ${INSTALL_DIR}"

# -------- concurrency-safe temps --------
TMP_TGZ="$(mktemp "/tmp/${IDE}-${VER}.XXXXXX.tar.gz")"
TMP_SHA="$(mktemp "/tmp/${IDE}-${VER}.XXXXXX.sha256")"

# --- Extract ---
STAGE_DIR="$(mktemp -d "/opt/.${IDE}-${VER}.stage.XXXXXX")"  # extract here first
LOCKFILE="/run/lock/jetbrains-${IDE}.lock"                   # per-IDE mutex
mkdir -p /run/lock || true

cleanup() {
  rm -f "$TMP_TGZ" "$TMP_SHA" 2>/dev/null || true
  rm -rf "$STAGE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# -------- optional: serialize per-IDE installs --------
# comment this block if you’re OK with parallel installs to different versions
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE"
  flock 9
fi

# --- Fetch ---
echo "Download from: $URL"
curl -fsSL -o "$TMP_TGZ" "$URL"

# checksum (if available)
if curl -fsSL -o "$TMP_SHA" "$SHA_URL" 2>/dev/null; then
  echo "Verifying checksum..."
  expected="$(awk '{print $1}' "$TMP_SHA")"
  actual="$(sha256sum "$TMP_TGZ" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || { echo "❌ SHA-256 mismatch"; exit 1; }
else
  echo "⚠️  No SHA-256 file found at ${SHA_URL}; skipping checksum verification."
fi

# -------- extract to a staging directory --------
tar -xzf "$TMP_TGZ" -C "$STAGE_DIR" --strip-components=1

# sanity check before touching the live path
if [[ ! -x "${STAGE_DIR}/bin/${IDE}.sh" && ! -x "${STAGE_DIR}/bin/${IDE}" ]]; then
  echo "❌ Installation appears incomplete in stage dir" >&2
  exit 1
fi

# -------- atomically replace the versioned install dir --------
# move the existing aside only after stage is ready
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "${INSTALL_DIR}.bak" 2>/dev/null || true
  mv -T "$INSTALL_DIR" "${INSTALL_DIR}.bak"
fi
mv -T "$STAGE_DIR" "$INSTALL_DIR"
# if we got here, stage moved; prevent cleanup from deleting it
STAGE_DIR=""

# permissions on the new tree
chown -R root:root "$INSTALL_DIR"
chmod -R a+rX "$INSTALL_DIR"
chmod -R go-w "$INSTALL_DIR"

# -------- atomically update the stable symlink --------
ln -sfn "$INSTALL_DIR" "$LINK_DIR"

# optional: clean old backup if everything looks good
rm -rf "${INSTALL_DIR}.bak" 2>/dev/null || true


# --- Create starter shim ---
cat > "${STARTER_FILE}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
source /etc/profile.d/60-cb-jdk--profile.sh"    2>/dev/null || true
source /etc/profile.d/53-cb-python--profile.sh" 2>/dev/null || true
exec "\${BASE_DIR}/bin/${IDE}" "\$@"
EOF
chmod 0755 "${STARTER_FILE}"

cat > "${SHIM_BIN}" <<EOF
#!/usr/bin/env bash
exec "$STARTER_FILE" "\$@"
EOF
chmod 0755 "$SHIM_BIN"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=${PRODUCT} ${VER}
Exec=${STARTER_FILE} %F
Icon=${INSTALL_DIR}/bin/${IDE}.png
Terminal=false
Categories=Development;IDE;
StartupWMClass=jetbrains-${IDE}
EOF
chmod 0644 "$DESKTOP_FILE"
update-desktop-database /usr/share/applications || true

echo "✅ Installed ${PRODUCT} ${VER}"
echo "▶ Run via '${IDE}'"
