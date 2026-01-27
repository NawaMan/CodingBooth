#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# ===================== Must be root =====================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/libs/skip-setup.sh"
if ! "$SCRIPT_DIR/cb-has-desktop.sh"; then
    skip_setup "$SCRIPT_NAME" "desktop environment not available"
fi

PROFILE_FILE="/etc/profile.d/70-cb-eclipse-gtk--profile.sh"

# Load JDK env exported by the base setup
source /etc/profile.d/60-cb-jdk--profile.sh 2>/dev/null || true

# ===================== Check Java =====================
if ! command -v java >/dev/null 2>&1; then
  echo "Error: 'java' command not found. Please install Java or ensure it's in your PATH." >&2
  exit 1
fi
if ! java -version >/dev/null 2>&1; then
  echo "Error: Java command exists but failed to run properly." >&2
  exit 1
fi

# ===================== Config =====================
MIRROR="${MIRROR:-https://download.eclipse.org/technology/epp/downloads/release}"
REL="${REL:-2025-09}"             # e.g. 2025-09
KIND="${KIND:-java}"              # e.g. java | jee
ARCH="$(uname -m)"                # use uname -m directly
INSTALL_DIR="/opt/eclipse-${KIND}-${REL}"

STARTER_FILE="${INSTALL_DIR}/eclipse-starter.sh"   # canonical starter
SHIM_BIN="/usr/local/bin/eclipse"                  # CLI shim -> STARTER_FILE
DESKTOP_FILE="/usr/share/applications/eclipse-${KIND}-${REL}.desktop"  # system app menu

# Desktop shortcut options
CREATE_USER_DESKTOP_ICONS="${CREATE_USER_DESKTOP_ICONS:-1}"  # 1=create, 0=skip
INCLUDE_SKEL="${INCLUDE_SKEL:-1}"                            # 1=also put in /etc/skel/Desktop

# ===================== Derived =====================
TARBALL="eclipse-${KIND}-${REL}-R-linux-gtk-${ARCH}.tar.gz"
URL="${MIRROR}/${REL}/R/${TARBALL}"
ICON_PATH="${INSTALL_DIR}/icon.xpm"

echo "• Installing Eclipse ${KIND} ${REL} for ${ARCH}"
echo "• From: ${URL}"
echo "• To:   ${INSTALL_DIR}"
echo "• Starter: ${STARTER_FILE}"
echo

# ===================== Fetch & extract =====================
mkdir -p /opt
wget -q --show-progress -O /tmp/eclipse.tgz "${URL}"

# Fresh install dir
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# If the tarball contains a top-level "eclipse/" directory (usual case), drop it:
# (Remove --strip-components=1 if your tarball has files at the root.)
tar -xf /tmp/eclipse.tgz -C "${INSTALL_DIR}" --strip-components=1

# Point the static link to the new install
ln -sfn "${INSTALL_DIR}" /opt/eclipse

echo "Installed to ${INSTALL_DIR} and linked /opt/eclipse -> ${INSTALL_DIR}"

# ===================== Permissions: read-only for users =====================
chown -R root:root "${INSTALL_DIR}"
chmod -R a+rX      "${INSTALL_DIR}"
chmod -R go-w      "${INSTALL_DIR}"

# ===================== Canonical STARTER_FILE =====================
cat > "$STARTER_FILE" <<'EOF'
#!/usr/bin/env bash
# Central starter for system Eclipse; used by both .desktop and /usr/local/bin shim.
# Workspace: ~/eclipse-workspace
# Java selection order:
#   1) ECLIPSE_VM env override (if set & executable)
#   2) 'java' from PATH
#   3) Bundled ./jre/bin/java
#   4) Bundled JustJ under ./plugins/org.eclipse.justj.*.jre*/jre/bin/java

set -Eeuo pipefail
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Implement the advertised Java search order
if [ -n "${ECLIPSE_VM:-}" ] && [ -x "${ECLIPSE_VM}" ]; then
  JAVA_BIN="${ECLIPSE_VM}"
elif command -v java >/dev/null 2>&1; then
  JAVA_BIN="$(command -v java)"
elif [ -x "${BASE_DIR}/jre/bin/java" ]; then
  JAVA_BIN="${BASE_DIR}/jre/bin/java"
else
  JAVA_BIN=""
  for cand in "${BASE_DIR}"/plugins/org.eclipse.justj.*.jre*/jre/bin/java; do
    if [ -x "$cand" ]; then JAVA_BIN="$cand"; break; fi
  done
fi

if [ -z "${JAVA_BIN:-}" ]; then
  echo "No suitable Java found (ECLIPSE_VM, system java, bundled ./jre, JustJ)." >&2
  exit 1
fi

exec "${BASE_DIR}/eclipse" \
  -vm "${JAVA_BIN}" \
  -data "${HOME}/eclipse-workspace" \
  "$@"
EOF
chmod 0755 "$STARTER_FILE"

# ===================== System-wide GTK env + info function =====================
cat >"$PROFILE_FILE" <<'EOF'
# Eclipse GTK settings (system-wide)
export SWT_GTK3=1          # Force GTK3 (modern)
export GDK_SCALE=1         # For HiDPI scaling if needed
export GDK_DPI_SCALE=1     # Adjust DPI if text looks off

# Print information about the system-wide Eclipse setup.
eclipse-setup-info() {
  SHIM="/usr/local/bin/eclipse"
  INSTALL_DIR="__INSTALL_DIR__"     # patched below
  STARTER_FILE="${INSTALL_DIR}/eclipse-starter.sh"
  REL="__REL__"
  KIND="__KIND__"

  echo "Eclipse setup information:"
  echo "  Shim:                ${SHIM}"
  echo "  Starter:             ${STARTER_FILE}"
  echo "  Install directory:   ${INSTALL_DIR}"

  BUILD=""
  if [ -f "${INSTALL_DIR}/configuration/config.ini" ]; then
    BUILD="$(grep -E '^eclipse.buildId=' "${INSTALL_DIR}/configuration/config.ini" 2>/dev/null | head -n1 | cut -d= -f2-)"
  fi
  if [ -n "${BUILD}" ]; then
    echo "  Eclipse version:     ${BUILD}"
  else
    echo "  Eclipse version:     ${REL} (${KIND})"
  fi

  echo "  Default workspace:   ${HOME}/eclipse-workspace"

  JAVA_BIN=""
  if [ -n "${ECLIPSE_VM:-}" ] && [ -x "${ECLIPSE_VM}" ]; then
    JAVA_BIN="${ECLIPSE_VM}"
  elif command -v java >/dev/null 2>&1; then
    JAVA_BIN="$(command -v java)"
  elif [ -x "${INSTALL_DIR}/jre/bin/java" ]; then
    JAVA_BIN="${INSTALL_DIR}/jre/bin/java"
  else
    for cand in "${INSTALL_DIR}"/plugins/org.eclipse.justj.*.jre*/jre/bin/java; do
      if [ -x "$cand" ]; then JAVA_BIN="$cand"; break; fi
    done
  fi

  if [ -n "${JAVA_BIN}" ]; then
    JV="$("$JAVA_BIN" -version 2>&1 | head -n1)"
    echo "  Java:                ${JV} (${JAVA_BIN})"
  else
    echo "  Java:                default"
  fi
}
EOF
chmod 0644 "$PROFILE_FILE"
# Patch placeholders
sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "$PROFILE_FILE"
sed -i "s|__REL__|${REL}|g" "$PROFILE_FILE"
sed -i "s|__KIND__|${KIND}|g" "$PROFILE_FILE"

# ===================== CLI shim =====================
cat > "${SHIM_BIN}" <<EOF
#!/usr/bin/env bash
exec "${STARTER_FILE}" "\$@"
EOF
chmod 0755 "${SHIM_BIN}"

# ===================== System app menu (.desktop) =====================
cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=Eclipse ${KIND^} ${REL}
Exec=${STARTER_FILE} %F
Icon=${ICON_PATH}
Terminal=false
Categories=Development;IDE;
StartupWMClass=Eclipse
EOF
chmod 0644 "${DESKTOP_FILE}"
command -v update-desktop-database >/dev/null 2>&1 && \
  update-desktop-database /usr/share/applications || true

echo
echo "✅ Eclipse installed at: ${INSTALL_DIR}"
echo "▶ Canonical starter:     ${STARTER_FILE}"
echo "▶ Launch via shim:       ${SHIM_BIN}"
echo "📁 Default workspace:    ~/eclipse-workspace (per user)"
echo "🧩 GTK env file:         ${PROFILE_FILE}"
echo "🖥  Desktop shortcut(s):  created=${CREATE_USER_DESKTOP_ICONS}, skel=${INCLUDE_SKEL}"
echo "ℹ️  Open a new shell and run:  eclipse-setup-info"
