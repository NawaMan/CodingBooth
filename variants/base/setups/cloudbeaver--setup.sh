#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [PORT]

Arguments:
  PORT  Port for the CloudBeaver web server (default: 8978)

Examples:
  $0           # install with default port 8978
  $0 18978     # use port 18978

Prerequisites:
- CloudBeaver must be pre-installed at /opt/cloudbeaver
  (typically via COPY --from=dbeaver/cloudbeaver:<version>)
- Java must be available either on PATH or at /opt/cloudbeaver-java

Notes:
- Creates a starter script at /usr/local/bin/start-cloudbeaver
- CloudBeaver web UI is accessible at http://localhost:<PORT>
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
CLOUDBEAVER_PORT="${1:-8978}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

CLOUDBEAVER_DIR="/opt/cloudbeaver"
CLOUDBEAVER_JAVA_DIR="/opt/cloudbeaver-java"
STARTUP_FILE="/usr/share/startup.d/70-cb-cloudbeaver--startup.sh"
PROFILE_FILE="/etc/profile.d/70-cb-cloudbeaver--profile.sh"
STARTER_FILE="/usr/local/bin/start-cloudbeaver"

# ---- verify CloudBeaver is present ----
if [[ ! -d "$CLOUDBEAVER_DIR/server" ]]; then
  echo "❌ CloudBeaver not found at $CLOUDBEAVER_DIR"
  echo "   Use COPY --from=dbeaver/cloudbeaver:<version> /opt/cloudbeaver /opt/cloudbeaver"
  exit 1
fi

# ---- verify Java is available ----
JAVA_BIN=""
if command -v java >/dev/null 2>&1; then
  JAVA_BIN="$(command -v java)"
  echo "• Using system Java: $JAVA_BIN"
elif [[ -x "$CLOUDBEAVER_JAVA_DIR/openjdk/bin/java" ]]; then
  JAVA_BIN="$CLOUDBEAVER_JAVA_DIR/openjdk/bin/java"
  echo "• Using bundled Java: $JAVA_BIN"
else
  echo "❌ Java not found. Either install JDK (setup jdk) or copy Java from CloudBeaver image:"
  echo "   COPY --from=dbeaver/cloudbeaver:<version> /opt/java /opt/cloudbeaver-java"
  exit 1
fi

JAVA_HOME_DIR="$(dirname "$(dirname "$JAVA_BIN")")"

# ---- ensure workspace directory exists ----
mkdir -p "$CLOUDBEAVER_DIR/workspace"

# ---- create profile script ----
cat > "${PROFILE_FILE}" <<PROFILE
# CloudBeaver environment
export CB_CLOUDBEAVER_HOME="${CLOUDBEAVER_DIR}"
export CB_CLOUDBEAVER_PORT="${CLOUDBEAVER_PORT}"

# Add bundled Java to PATH if not already available
if [[ -d "${JAVA_HOME_DIR}/bin" ]]; then
  case ":\$PATH:" in
    *":${JAVA_HOME_DIR}/bin:"*) ;;
    *) export PATH="${JAVA_HOME_DIR}/bin:\$PATH" ;;
  esac
fi

cloudbeaver--info() {
  echo "CloudBeaver"
  echo "  Home:    ${CLOUDBEAVER_DIR}"
  echo "  Port:    ${CLOUDBEAVER_PORT}"
  echo "  Java:    ${JAVA_HOME_DIR}"
  echo "  Starter: ${STARTER_FILE}"
  echo "  URL:     http://localhost:${CLOUDBEAVER_PORT}"
}
PROFILE
chmod 644 "${PROFILE_FILE}"

# ---- create startup script (runs at container boot) ----
mkdir -p "$(dirname "$STARTUP_FILE")"
cat > "${STARTUP_FILE}" <<'STARTUP'
#!/usr/bin/env bash
# CloudBeaver startup — initialize workspace if needed
set -euo pipefail

CB_DIR="__CLOUDBEAVER_DIR__"
CB_WORKSPACE="$CB_DIR/workspace"

# Ensure workspace is owned by current user
if [[ -d "$CB_WORKSPACE" ]]; then
  if [[ ! -w "$CB_WORKSPACE" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$CB_WORKSPACE"
  fi
fi

# Initialize workspace metadata if first run
if [[ ! -d "$CB_WORKSPACE/.metadata" ]]; then
  mkdir -p "$CB_WORKSPACE/.metadata"
  mkdir -p "$CB_WORKSPACE/GlobalConfiguration/.dbeaver"
  if [[ -f "$CB_DIR/conf/initial-data-sources.conf" && \
        ! -f "$CB_WORKSPACE/GlobalConfiguration/.dbeaver/data-sources.json" ]]; then
    cp "$CB_DIR/conf/initial-data-sources.conf" \
       "$CB_WORKSPACE/GlobalConfiguration/.dbeaver/data-sources.json"
  fi
fi
STARTUP
sed -i "s|__CLOUDBEAVER_DIR__|${CLOUDBEAVER_DIR}|g" "${STARTUP_FILE}"
chmod 755 "${STARTUP_FILE}"

# ---- create starter script (manual foreground launch) ----
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-__CLOUDBEAVER_PORT__}
CB_DIR="__CLOUDBEAVER_DIR__"
JAVA_HOME_DIR="__JAVA_HOME_DIR__"

# Ensure Java is on PATH
export PATH="${JAVA_HOME_DIR}/bin:$PATH"

cd "$CB_DIR"

launcherJar=( server/plugins/org.jkiss.dbeaver.launcher*.jar )
if [[ ! -f "${launcherJar[0]}" ]]; then
  echo "❌ CloudBeaver launcher not found in $CB_DIR/server/plugins/"
  exit 1
fi

echo "Starting CloudBeaver on http://localhost:$PORT ..."

exec java ${JAVA_OPTS:-} \
  -Dfile.encoding=UTF-8 \
  --add-modules=ALL-DEFAULT \
  --add-opens=java.base/java.io=ALL-UNNAMED \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens=java.base/java.net=ALL-UNNAMED \
  --add-opens=java.base/java.nio=ALL-UNNAMED \
  --add-opens=java.base/java.nio.charset=ALL-UNNAMED \
  --add-opens=java.base/java.text=ALL-UNNAMED \
  --add-opens=java.base/java.time=ALL-UNNAMED \
  --add-opens=java.base/java.util=ALL-UNNAMED \
  --add-opens=java.base/java.util.concurrent=ALL-UNNAMED \
  --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.vm=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
  --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
  --add-opens=java.base/sun.security.ssl=ALL-UNNAMED \
  --add-opens=java.base/sun.security.action=ALL-UNNAMED \
  --add-opens=java.base/sun.security.util=ALL-UNNAMED \
  --add-opens=java.security.jgss/sun.security.jgss=ALL-UNNAMED \
  --add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED \
  --add-opens=java.sql/java.sql=ALL-UNNAMED \
  -jar "${launcherJar[0]}" \
  -product io.cloudbeaver.product.ce.product \
  -web-config conf/cloudbeaver.conf \
  -nl en \
  -registryMultiLanguage
STARTER
sed -i "s|__CLOUDBEAVER_PORT__|${CLOUDBEAVER_PORT}|g" "${STARTER_FILE}"
sed -i "s|__CLOUDBEAVER_DIR__|${CLOUDBEAVER_DIR}|g" "${STARTER_FILE}"
sed -i "s|__JAVA_HOME_DIR__|${JAVA_HOME_DIR}|g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- summary ----
echo ""
echo "✅ CloudBeaver setup complete."
echo "   Location:  ${CLOUDBEAVER_DIR}"
echo "   Port:      ${CLOUDBEAVER_PORT}"
echo "   Java:      ${JAVA_HOME_DIR}"
echo "   Starter:   ${STARTER_FILE}"
echo ""
echo "ℹ️  Launch manually: start-cloudbeaver [PORT]"
echo "   Access: http://localhost:${CLOUDBEAVER_PORT}"
