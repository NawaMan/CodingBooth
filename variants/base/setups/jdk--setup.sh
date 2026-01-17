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
#   1) CLI arg #2 (e.g., "graalvm") → sets JBANG_JDK_VENDOR
#   2) Existing JBANG_JDK_VENDOR env
#   3) Fallback default: temurin
#
# Also supports:
#   --alternative <PRIORITY>  # update-alternatives priority (default: 20000)
#
# Usage:
#   sudo ./jdk--setup.sh
#   sudo ./jdk--setup.sh 25
#   sudo ./jdk--setup.sh 25 graalvm
#   sudo ./jdk--setup.sh --alternative 30000 25 temurin
# ---------------------------------------------

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
die() { echo "❌ $*" >&2; exit 1; }

# --- Root check ---
[[ "${EUID}" -eq 0 ]] || die "This script must be run as root (use sudo)."

PROFILE_FILE="/etc/profile.d/60-ws-jdk--profile.sh"
STARTUP_FILE="/usr/share/startup.d/60-ws-jdk--startup.sh"

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

Examples:
  sudo ./jdk--setup.sh
  sudo ./jdk--setup.sh 25
  sudo ./jdk--setup.sh 25 graalvm
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
  export JBANG_JDK_VENDOR="$CLI_VENDOR"
fi
: "${JBANG_JDK_VENDOR:=temurin}"
ACTIVE_VENDOR="$JBANG_JDK_VENDOR"

# --- JBang dirs ---
export JBANG_DIR=/opt/jbang-home
export JBANG_CACHE_DIR=/opt/jbang-cache
mkdir -p "$JBANG_DIR" "$JBANG_CACHE_DIR"
chmod -R 0777 "$JBANG_DIR" "$JBANG_CACHE_DIR"

# --- Install JBang ---
log "Installing JBang..."
curl -Ls https://sh.jbang.dev | bash -s - app setup
install -Dm755 "${JBANG_DIR}/bin/jbang" /usr/local/bin/jbang

# --- Install JDK (via JBang) ---
log "Installing JDK ${JDK_VERSION} (vendor: ${ACTIVE_VENDOR}) via JBang..."
jbang jdk install "${JDK_VERSION}" || die "JBang failed to install JDK ${JDK_VERSION}"

# --- Resolve JAVA_HOME (canonical path) ---
# IMPORTANT: canonicalize to avoid pointing at .../jbang-home/currentjdk
JDK_HOME_RAW="$(jbang jdk home "${JDK_VERSION}")"
[[ -n "$JDK_HOME_RAW" && -e "$JDK_HOME_RAW" ]] || die "Could not resolve JDK home for ${JDK_VERSION} (${ACTIVE_VENDOR})."
JDK_HOME="$(readlink -f -- "$JDK_HOME_RAW")"
[[ -d "$JDK_HOME" ]] || die "Resolved JDK_HOME is not a directory: $JDK_HOME"

# --- Stable symlinks ---
GENERIC_LINK="/opt/jdk${JDK_VERSION}"
VENDOR_LINK="/opt/jdk-${JDK_VERSION}-${ACTIVE_VENDOR}"
STATIC_LINK="/opt/jdk"

log "Creating symlinks: ${GENERIC_LINK}, ${VENDOR_LINK}, and ${STATIC_LINK}"

ln -snf "$JDK_HOME" "$GENERIC_LINK"
ln -snf "$JDK_HOME" "$VENDOR_LINK"

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

# --- Optional GraalVM extras ---
if [[ "${ACTIVE_VENDOR}" == "graalvm" ]]; then
  log "GraalVM selected; attempting to install native-image (optional)..."
  if command -v gu >/dev/null 2>&1; then
    gu install native-image || true
  elif [[ -x "${JAVA_HOME}/bin/gu" ]]; then
    "${JAVA_HOME}/bin/gu" install native-image || true
  else
    log "Graal 'gu' not found; skipping native-image."
  fi
fi

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
