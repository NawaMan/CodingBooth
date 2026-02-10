#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# ---------------------------------------------
# jdk--setup.sh — Install JBang + chosen JDK
#
# Vendor selection order:
#   1) CLI arg #2 (e.g., "corretto") → sets vendor
#   2) Existing JBANG_JDK_VENDOR env
#   3) Fallback default: temurin
#
# JDK download strategy:
#   - temurin:  direct download from Adoptium API (fast, reliable)
#   - corretto: direct download from AWS (fast, reliable)
#   - others:   fallback to JBang's JDK installer (supports many
#               vendors but can be flaky)
#
# Also supports:
#   --alternative <PRIORITY>  # update-alternatives priority (default: 20000)
#
# Usage:
#   sudo ./jdk--setup.sh
#   sudo ./jdk--setup.sh 25
#   sudo ./jdk--setup.sh 25 corretto
#   sudo ./jdk--setup.sh 25 openjdk
#   sudo ./jdk--setup.sh --alternative 30000 25 temurin
# ---------------------------------------------

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
die() { echo "❌ $*" >&2; exit 1; }

# --- Root check ---
[[ "${EUID}" -eq 0 ]] || die "This script must be run as root (use sudo)."

# This script will always be installed by root.
HOME=/root


PROFILE_FILE="/etc/profile.d/60-cb-jdk--profile.sh"
STARTUP_FILE="/usr/share/startup.d/60-cb-jdk--startup.sh"

# --- Defaults ---
JDK_VERSION="21"
CLI_VENDOR=""
ALT_PRIO="20000"

# --- Parse args (flags first, then positionals: version vendor) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --alternative)
      ALT_PRIO="${2:-}"
      [[ -n "$ALT_PRIO" && "$ALT_PRIO" =~ ^[0-9]+$ ]] || die "--alternative requires a numeric priority"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: jdk--setup.sh [--alternative PRIORITY] [JDK_VERSION] [VENDOR]

Supported vendors:
  temurin   (default) — direct download from Adoptium API
  corretto            — direct download from AWS
  Any other vendor supported by JBang (e.g., openjdk, graalvm)
    will use JBang as a fallback installer.

Examples:
  sudo ./jdk--setup.sh
  sudo ./jdk--setup.sh 25
  sudo ./jdk--setup.sh 25 corretto
  sudo ./jdk--setup.sh 25 openjdk
  sudo ./jdk--setup.sh --alternative 30000 25 temurin
USAGE
      exit 0
      ;;
    --*) die "Unknown option: $1" ;;
    *)
      if [[ "$JDK_VERSION" == "21" && "$1" =~ ^[0-9]+$ ]]; then
        JDK_VERSION="$1"
      elif [[ -z "$CLI_VENDOR" ]]; then
        CLI_VENDOR="$1"
      else
        die "Unexpected extra argument: $1"
      fi
      shift
      ;;
  esac
done

# --- Vendor policy ---
if [[ -n "$CLI_VENDOR" ]]; then
  ACTIVE_VENDOR="$CLI_VENDOR"
elif [[ -n "${JBANG_JDK_VENDOR:-}" ]]; then
  ACTIVE_VENDOR="$JBANG_JDK_VENDOR"
else
  ACTIVE_VENDOR="temurin"
fi

# --- Detect architecture ---
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64)  ARCH="x64"    ;;
  aarch64) ARCH="aarch64" ;;
  *)       die "Unsupported architecture: $MACHINE" ;;
esac

# --- Build download URL based on vendor ---
# Returns a URL for direct download, or "jbang" to signal fallback.
build_download_url() {
  local version="$1"
  local vendor="$2"
  local arch="$3"

  case "$vendor" in
    temurin)
      echo "https://api.adoptium.net/v3/binary/latest/${version}/ga/linux/${arch}/jdk/hotspot/normal/eclipse"
      ;;
    corretto)
      echo "https://corretto.aws/downloads/latest/amazon-corretto-${version}-${arch}-linux-jdk.tar.gz"
      ;;
    *)
      # Love JBang (Thanks Max Rydahl Andersen), but downloading JDK from it outage more than a few times.
      # So only use JBang for something else.
      echo "jbang"
      ;;
  esac
}

# --- JBang dirs ---
export JBANG_DIR=/opt/jbang-home
export JBANG_CACHE_DIR=/opt/jbang-cache
mkdir -p "$JBANG_DIR" "$JBANG_CACHE_DIR"
chmod -R 0777 "$JBANG_DIR" "$JBANG_CACHE_DIR"

# --- Install JBang (still useful as a Java scripting tool) ---
log "Installing JBang..."
export JBANG_JDK_VENDOR="$ACTIVE_VENDOR"
curl -Ls https://sh.jbang.dev | bash -s - app setup
install -Dm755 "${JBANG_DIR}/bin/jbang" /usr/local/bin/jbang

# --- Install JDK ---
JDK_INSTALL_DIR="/opt/jdk-installs/${JDK_VERSION}-${ACTIVE_VENDOR}"
DOWNLOAD_URL="$(build_download_url "$JDK_VERSION" "$ACTIVE_VENDOR" "$ARCH")"

if [[ "$DOWNLOAD_URL" != "jbang" ]]; then
  # --- Direct download (temurin, corretto) ---
  log "Downloading JDK ${JDK_VERSION} (vendor: ${ACTIVE_VENDOR}, arch: ${ARCH})..."
  log "URL: ${DOWNLOAD_URL}"

  TMP_TARBALL="/tmp/jdk-${JDK_VERSION}-${ACTIVE_VENDOR}.tar.gz"
  HTTP_CODE="$(curl -fSL -w '%{http_code}' -o "$TMP_TARBALL" "$DOWNLOAD_URL" 2>/dev/null)" \
    || die "Failed to download JDK ${JDK_VERSION} from ${ACTIVE_VENDOR} (HTTP ${HTTP_CODE:-???})"

  [[ -s "$TMP_TARBALL" ]] || die "Downloaded file is empty"

  log "Extracting JDK..."
  mkdir -p "$JDK_INSTALL_DIR"
  tar -xzf "$TMP_TARBALL" -C "$JDK_INSTALL_DIR" --strip-components=1
  rm -f "$TMP_TARBALL"
else
  # --- JBang fallback (openjdk, graalvm, etc.) ---
  log "⚠️  No direct download available for vendor '${ACTIVE_VENDOR}'. Using JBang as fallback."
  log "    If this fails, try: temurin or corretto"
  export JBANG_JDK_VENDOR="$ACTIVE_VENDOR"
  jbang jdk install "${JDK_VERSION}" || die "JBang failed to install JDK ${JDK_VERSION} (${ACTIVE_VENDOR})"

  JDK_HOME_RAW="$(jbang jdk home "${JDK_VERSION}")"
  [[ -n "$JDK_HOME_RAW" && -e "$JDK_HOME_RAW" ]] \
    || die "Could not resolve JDK home for ${JDK_VERSION} (${ACTIVE_VENDOR})."

  # Copy to standard location so the rest of the script works uniformly
  mkdir -p "$JDK_INSTALL_DIR"
  cp -a "$(readlink -f "$JDK_HOME_RAW")/." "$JDK_INSTALL_DIR/"
fi

# --- Resolve JAVA_HOME (canonical path) ---
JDK_HOME="$(readlink -f -- "$JDK_INSTALL_DIR")"
[[ -d "$JDK_HOME" && -x "$JDK_HOME/bin/java" ]] \
  || die "JDK installation invalid: $JDK_HOME/bin/java not found"

# --- Tell JBang about this JDK so it can use it ---
jbang jdk install "$JDK_VERSION" "$JDK_HOME" 2>/dev/null || true

# --- Stable symlinks ---
GENERIC_LINK="/opt/jdk${JDK_VERSION}"
VENDOR_LINK="/opt/jdk-${JDK_VERSION}-${ACTIVE_VENDOR}"
STATIC_LINK="/opt/jdk"

log "Creating symlinks: ${GENERIC_LINK}, ${VENDOR_LINK}, and ${STATIC_LINK}"

ln -snf "$JDK_HOME" "$GENERIC_LINK"
# VENDOR_LINK is the install dir itself, create symlink only if different
if [[ "$(readlink -f "$VENDOR_LINK")" != "$JDK_HOME" ]]; then
  ln -snf "$JDK_HOME" "$VENDOR_LINK"
fi

# Ensure STATIC_LINK does not exist before recreating
if [ -e "$STATIC_LINK" ] || [ -L "$STATIC_LINK" ]; then
    log "Removing existing static link or directory: ${STATIC_LINK}"
    rm -rf "$STATIC_LINK"
fi
ln -s "$JDK_HOME" "$STATIC_LINK"

# --- Export for current shell ---
export JAVA_HOME="$GENERIC_LINK"
export "JAVA_${JDK_VERSION}_HOME=$GENERIC_LINK"
# PATH: append JAVA_HOME/bin (never prepend), guard against duplicates
case ":$PATH:" in
  *":$JAVA_HOME/bin:"*) : ;;
  *) export PATH="$PATH:$JAVA_HOME/bin" ;;
esac

# --- Register with update-alternatives (system-wide) ---
log "Registering JDK ${JDK_VERSION} with update-alternatives (priority ${ALT_PRIO})..."
update-alternatives --install /usr/bin/java   java   "${GENERIC_LINK}/bin/java"   "${ALT_PRIO}"
update-alternatives --install /usr/bin/javac  javac  "${GENERIC_LINK}/bin/javac"  "${ALT_PRIO}"
update-alternatives --install /usr/bin/jar    jar    "${GENERIC_LINK}/bin/jar"    "${ALT_PRIO}"
update-alternatives --install /usr/bin/jcmd   jcmd   "${GENERIC_LINK}/bin/jcmd"   "${ALT_PRIO}"
update-alternatives --install /usr/bin/jps    jps    "${GENERIC_LINK}/bin/jps"    "${ALT_PRIO}"
update-alternatives --install /usr/bin/jstack jstack "${GENERIC_LINK}/bin/jstack" "${ALT_PRIO}"
# Force-select our entries (best-effort for non-JDK tools)
update-alternatives --set java   "${GENERIC_LINK}/bin/java"
update-alternatives --set javac  "${GENERIC_LINK}/bin/javac"  || true
update-alternatives --set jar    "${GENERIC_LINK}/bin/jar"    || true
update-alternatives --set jcmd   "${GENERIC_LINK}/bin/jcmd"   || true
update-alternatives --set jps    "${GENERIC_LINK}/bin/jps"    || true
update-alternatives --set jstack "${GENERIC_LINK}/bin/jstack" || true

# --- System-wide profile for future shells ---
log "Writing ${PROFILE_FILE} ..."
cat >"$PROFILE_FILE" <<EOF
# JDK (${JDK_VERSION}) setup — managed by jdk--setup.sh
export JAVA_HOME=${GENERIC_LINK}
export JAVA_${JDK_VERSION}_HOME=${GENERIC_LINK}
export JAVA_HOME_${JDK_VERSION}_VENDOR=${VENDOR_LINK}

# Keep JAVA_HOME/bin at the end so version managers (e.g., jenv shims) can take precedence.
case ":\$PATH:" in
  *":\$JAVA_HOME/bin:"*) : ;;
  *) export PATH="\$PATH:\$JAVA_HOME/bin" ;;
esac

export CB_JDK_VERSION=${JDK_VERSION}
export CB_JAVA_HOME=${JAVA_HOME}

# Inspector: jdk-setup-info
jdk_setup_info() {
  set -o pipefail
  _hdr() { printf "\n\033[1m%s\033[0m\n" "\$*"; }
  _ok()  { printf "✅ %s\n" "\$*"; }
  _warn(){ printf "⚠️  %s\n" "\$*"; }
  _err() { printf "❌ %s\n" "\$*"; }

  _hdr "Java (system)"
  if command -v java >/dev/null 2>&1; then
    _ok "which java: \$(command -v java)"
    _ok "real java:  \$(readlink -f \$(command -v java))"
    java -version 2>&1 | sed 's/^/  /'
  else
    _err "java not found on PATH"
  fi

  _hdr "Environment"
  printf "JAVA_HOME=%s\n" "\${JAVA_HOME:-}"
  printf "JAVA_${JDK_VERSION}_HOME=%s\n" "\${JAVA_${JDK_VERSION}_HOME:-}"
  printf "Vendor link=%s\n" "\${JAVA_HOME_${JDK_VERSION}_VENDOR:-}"

  _hdr "JBang"
  if command -v jbang >/dev/null 2>&1; then
    _ok "jbang: \$(jbang --version 2>/dev/null | head -n1)"
    _ok "jdk home (raw): \$(jbang jdk home ${JDK_VERSION} 2>/dev/null || echo n/a)"
    _ok "installed jdks:"
    jbang jdk list 2>/dev/null | sed 's/^/  /' || true
  else
    _warn "jbang not found on PATH"
  fi

  _hdr "Alternatives"
  update-alternatives --display java   2>/dev/null | sed 's/^/  /' || true
}
alias jdk-setup-info='jdk_setup_info'
EOF
chmod 0644 "$PROFILE_FILE"

log "Writing ${STARTUP_FILE} ..."
export JDK_HOME
envsubst '$JDK_HOME' > ${STARTUP_FILE} <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for jdk_name in $(ls /opt 2>/dev/null | grep -E '^jdk[0-9]+$' || true); do
  jenv add "/opt/$jdk_name" >/dev/null 2>&1 || true
done

jenv local "$JDK_HOME" >/dev/null 2>&1 || true

EOF
chmod 755 "${STARTUP_FILE}"

# --- Summary ---
echo "✅ JDK ${JDK_VERSION} (${ACTIVE_VENDOR}) installed."
echo "   JAVA_HOME = ${GENERIC_LINK}"
echo "   JAVA_${JDK_VERSION}_HOME = ${GENERIC_LINK}"
echo "   Vendor link = ${VENDOR_LINK}"
echo "   Alternatives priority = ${ALT_PRIO}"
echo "   JBang launcher = /usr/local/bin/jbang"
echo "   Profile script = ${PROFILE_FILE}"
echo "   Alternatives:   \$(command -v java) -> \$(readlink -f \"\$(command -v java)\")"
echo
echo "Use it now in this shell (without reopening):"
echo "  . ${PROFILE_FILE} && jdk-setup-info"

export CB_JDK_VERSION=${JDK_VERSION}
export CB_JAVA_HOME=${JAVA_HOME}
