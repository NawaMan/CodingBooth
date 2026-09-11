#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest] [--port <PORT>]

Examples:
  $0                            # install latest sql-studio, port 3030
  $0 --version 0.1.53           # pin specific version
  $0 --port 13030               # use a different default port

Notes:
- Installs sql-studio to /usr/local/bin/sql-studio
- Supports amd64 and arm64
- Registers a desktop icon on desktop variants; clicking it (or running
  start-sql-studio with no arguments in a desktop session) asks what to
  open via a zenity dialog, falling back to a sample database if zenity
  is unavailable (headless/base variant) or the dialog is cancelled
- The CLI works on every variant regardless
- Not part of the base image by default: select the sql-studio template
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_DIR="$(dirname "$0")"

# ---- defaults / args ----
SQLSTUDIO_DEFAULT_VER="0.1.53"   # fallback when 'latest' cannot be resolved
REQ_VER="latest"
PORT="3030"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    --port)    shift; PORT="${1:-3030}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch mapping ----
# sql-studio's release assets are named after Rust target triples, not the
# amd64/arm64 dpkg reports.
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) TARGET="x86_64-unknown-linux-gnu" ;;
  arm64) TARGET="aarch64-unknown-linux-gnu" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# The base image already carries curl, tar, and ca-certificates; only pay for
# apt when this script is run somewhere leaner.
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
# sql-studio tags releases without a leading "v" (e.g. "0.1.53"), unlike
# lazygit/duckdb/sqluv — the regex below does not assume one.
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/frectonz/sql-studio/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 \
            | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See lazygit--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest sql-studio release; using ${SQLSTUDIO_DEFAULT_VER}."
    VERSION="$SQLSTUDIO_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install sql-studio ----
echo "⬇️  Installing sql-studio v${VERSION} (${TARGET}) ..."
TMP_DIR=$(mktemp -d)
ASSET="sql-studio-${TARGET}"
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/frectonz/sql-studio/releases/download/${VERSION}/${ASSET}.tar.xz" \
  -o "${TMP_DIR}/sql-studio.tar.xz"
tar -xJf "${TMP_DIR}/sql-studio.tar.xz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/${ASSET}/sql-studio" /usr/local/bin/sql-studio
rm -rf "${TMP_DIR}"

# ---- profile: env + info helper ----
PROFILE_FILE="/etc/profile.d/70-cb-sql-studio--profile.sh"
cat > "${PROFILE_FILE}" <<PROFILE
# sql-studio environment
export SQLSTUDIO_PORT="${PORT}"

sql-studio--info() {
  echo "sql-studio"
  echo "  Port:    \${SQLSTUDIO_PORT}"
  echo "  Starter: start-sql-studio"
  echo "  URL:     http://localhost:\${SQLSTUDIO_PORT}"
}
PROFILE
chmod 644 "${PROFILE_FILE}"

# ---- starter script (manual foreground launch, also used by the web icon) ----
STARTER_FILE="/usr/local/bin/start-sql-studio"
cat > "${STARTER_FILE}" <<'STARTER'
#!/usr/bin/env bash
set -euo pipefail

PORT="${SQLSTUDIO_PORT:-__PORT__}"

run_preview() {
  # sql-studio's "preview" magic path builds and opens a small sample SQLite
  # database, so there is always something to look at as a last resort. Only
  # this path needs its own directory — a real target must resolve relative
  # to the caller's own cwd, not get silently rebased underneath it.
  DATA_DIR="${HOME:-/tmp}/.local/share/sql-studio"
  mkdir -p "$DATA_DIR"
  cd "$DATA_DIR"
  exec sql-studio --address "0.0.0.0:${PORT}" --no-browser sqlite preview
}

if [ "$#" -eq 0 ]; then
  # No target given on the command line — typically the desktop icon's first
  # click. On a desktop session (zenity present) ask what to open instead of
  # silently defaulting; a headless/base-variant terminal has no zenity, so
  # it falls straight through to the sample preview.
  if command -v zenity >/dev/null 2>&1; then
    CHOICE=$(zenity --list --title="sql-studio" \
      --text="What do you want to explore?" \
      --column="Choose a data source" \
      "Sample data (preview)" \
      "SQLite file..." \
      "CSV file..." \
      "DuckDB file..." \
      "PostgreSQL connection..." \
      "MySQL connection..." \
      --height=320 --width=420) || CHOICE=""

    case "$CHOICE" in
      "SQLite file...")
        FILE=$(zenity --file-selection --title="Choose a SQLite database" --filename="${HOME}/code/") || FILE=""
        [ -n "$FILE" ] && exec sql-studio --address "0.0.0.0:${PORT}" --no-browser sqlite "$FILE"
        ;;
      "CSV file...")
        FILE=$(zenity --file-selection --title="Choose a CSV file" --filename="${HOME}/code/") || FILE=""
        [ -n "$FILE" ] && exec sql-studio --address "0.0.0.0:${PORT}" --no-browser csv "$FILE"
        ;;
      "DuckDB file...")
        FILE=$(zenity --file-selection --title="Choose a DuckDB database" --filename="${HOME}/code/") || FILE=""
        [ -n "$FILE" ] && exec sql-studio --address "0.0.0.0:${PORT}" --no-browser duckdb "$FILE"
        ;;
      "PostgreSQL connection...")
        URL=$(zenity --entry --title="PostgreSQL connection" \
          --text="Connection URL. (CodingBooth's postgresql setup: host localhost, user $(whoami), no password, database 'postgres'.)" \
          --entry-text="postgres://$(whoami)@localhost:5432/postgres") || URL=""
        [ -n "$URL" ] && exec sql-studio --address "0.0.0.0:${PORT}" --no-browser postgres "$URL"
        ;;
      "MySQL connection...")
        URL=$(zenity --entry --title="MySQL connection" \
          --text="Connection URL. (CodingBooth's mysql setup: host localhost, user $(whoami), no password.)" \
          --entry-text="mysql://$(whoami)@localhost:3306/") || URL=""
        [ -n "$URL" ] && exec sql-studio --address "0.0.0.0:${PORT}" --no-browser mysql "$URL"
        ;;
    esac
    # "Sample data (preview)", Cancel, or an empty answer all land here.
  fi
  run_preview
else
  exec sql-studio --address "0.0.0.0:${PORT}" --no-browser "$@"
fi
STARTER
sed -i "s|__PORT__|${PORT}|g" "${STARTER_FILE}"
chmod 755 "${STARTER_FILE}"

# ---- desktop icon (opens the preview sample; no-ops off-desktop) ----
cb-web-icon.sh --id sql-studio --name "sql-studio" --icon applications-internet \
  --port-env SQLSTUDIO_PORT --port "${PORT}" \
  --path / --start start-sql-studio

# ---- friendly summary ----
echo ""
echo "✅ sql-studio installed."
echo -n "   sql-studio → "; sql-studio --version 2>/dev/null || true

cat <<EON
ℹ️ Ready to use:
- Explore a SQLite file: start-sql-studio sqlite mydata.db
- Explore a DuckDB file: start-sql-studio duckdb mydata.duckdb
- No file at hand yet:   start-sql-studio        # asks what to open (desktop), else a sample database
- Reach it from the host: booth--expose ${PORT}

Notes:
- sql-studio is a single binary that serves a browser-based SQL explorer for
  SQLite, libSQL, PostgreSQL, MySQL, DuckDB, ClickHouse, SQL Server, and
  local Parquet/CSV files — one file or connection at a time, on \$SQLSTUDIO_PORT
  (default ${PORT}).
- If this booth also has CodingBooth's PostgreSQL or MySQL setup, both
  default to: host localhost, user "\$(whoami)" (usually "coder"), no
  password, default port. Neither setup creates a database matching that
  user, so point at one that actually exists — e.g.
    start-sql-studio postgres "postgres://coder@localhost:5432/postgres"
    start-sql-studio mysql "mysql://coder@localhost:3306/"
- See: https://github.com/frectonz/sql-studio
EON
