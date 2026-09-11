#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Usage in Boothfile:  setup jetbrains-import-project <ide>
#   <ide> is any JetBrains IDE name jetbrains--setup.sh installs (clion, goland,
#   phpstorm, pycharm, rider, rubymine, webstorm, ...).
#
# Every JetBrains IDE jetbrains--setup.sh installs shares the same layout: a stable
# /opt/<ide> symlink and a self-contained starter script at /opt/<ide>/<ide>-starter
# that both the CLI shim (/usr/local/bin/<ide>) and the .desktop Exec line funnel
# through. Opening a folder with these IDEs (unlike Eclipse) needs no separate
# workspace registration -- it just works, no import wizard -- so the only gap is
# getting there without typing a path: this patches the starter to default to
# opening the project directory when launched with no arguments.
#
# This is deliberately the IDEA extension's starter-patch half only. IDEA's extra
# `gradle idea` pre-generation step exists to dodge a Gradle-vs-Eclipse build-system
# prompt that is specific to JVM projects; Python/Go/PHP/Ruby/C++/.NET projects have
# no such ambiguity, so there is nothing to pre-generate here.

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

IDE="${1:-}"
if [ -z "$IDE" ]; then
  echo "❌ Usage: jetbrains-import-project--setup.sh <ide>" >&2
  exit 1
fi

IDE_DIR="$(readlink -f "/opt/${IDE}" 2>/dev/null || true)"
if [ -z "$IDE_DIR" ] || [ ! -d "$IDE_DIR/bin" ]; then
  skip_setup "$SCRIPT_NAME" "${IDE} not installed (select '${IDE}' before 'jetbrains-import-project')"
fi

STARTER_FILE="${IDE_DIR}/${IDE}-starter"
if [ ! -f "$STARTER_FILE" ]; then
  skip_setup "$SCRIPT_NAME" "starter script not found at ${STARTER_FILE}"
fi

# --- Patch the starter: default to opening the project when launched bare ---
# Both /usr/local/bin/<ide> (the CLI shim) and the .desktop Exec line just forward
# their args to this starter, so patching it here covers both launch paths.
cat > "$STARTER_FILE" <<STARTEREOF
#!/usr/bin/env bash
set -Eeuo pipefail
BASE_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
[ -f /etc/profile.d/60-cb-jdk--profile.sh    ] && source /etc/profile.d/60-cb-jdk--profile.sh    2>/dev/null || true
[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
if [ "\$#" -eq 0 ] && [ -d "\${CODE_DIR:-\$HOME/code}" ]; then
  set -- "\${CODE_DIR:-\$HOME/code}"
fi
exec "\${BASE_DIR}/bin/${IDE}" "\$@"
STARTEREOF
chmod 0755 "$STARTER_FILE"

echo "✅ ${IDE} starter patched to open ~/code by default: ${STARTER_FILE}"
