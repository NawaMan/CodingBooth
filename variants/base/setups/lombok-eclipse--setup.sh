#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO while running: $BASH_COMMAND" >&2' ERR

# Fixed Eclipse path per your setup
ECLIPSE_HOME="/opt/eclipse"
ECLIPSE_INI="${ECLIPSE_HOME}/eclipse.ini"
LOMBOK_JAR="${ECLIPSE_HOME}/lombok.jar"
LOMBOK_URL="${LOMBOK_URL:-https://projectlombok.org/downloads/lombok.jar}"

# Must be root to write under /opt
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Sanity checks
[[ -f "${ECLIPSE_INI}" ]] || { echo "eclipse.ini not found at ${ECLIPSE_INI}"; exit 1; }

# Fetch Lombok
echo "Downloading Lombok from: ${LOMBOK_URL}"
wget -O "${LOMBOK_JAR}.tmp" "${LOMBOK_URL}"
mv -f "${LOMBOK_JAR}.tmp" "${LOMBOK_JAR}"
chmod a+r "${LOMBOK_JAR}"

# Lines we want to ensure (append-only)
JAVAAGENT_LINE="-javaagent:${LOMBOK_JAR}"
BOOTCLASS_LINE="-Xbootclasspath/a:${LOMBOK_JAR}"

# Append only if not present (no awk/sed)
if ! grep -Fqx -- "${JAVAAGENT_LINE}" "${ECLIPSE_INI}"; then
  echo "${JAVAAGENT_LINE}" >> "${ECLIPSE_INI}"
fi
if ! grep -Fqx -- "${BOOTCLASS_LINE}" "${ECLIPSE_INI}"; then
  echo "${BOOTCLASS_LINE}" >> "${ECLIPSE_INI}"
fi

echo "✅ Lombok jar: ${LOMBOK_JAR}"
echo "🧩 Appended to eclipse.ini (if missing):"
echo "   ${JAVAAGENT_LINE}"
echo "   ${BOOTCLASS_LINE}"
echo "ℹ️ Note: this appends at the end of eclipse.ini (not before -vmargs). If you ever need strict placement, we’d have to edit the file rather than just append."
