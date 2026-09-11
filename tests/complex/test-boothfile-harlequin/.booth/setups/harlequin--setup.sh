#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install latest Harlequin
  $0 --version 2.13.0        # pin specific version

Notes:
- Installs Harlequin into an isolated venv at /opt/harlequin
- Symlinks harlequin to /usr/local/bin/harlequin
- Requires python3 (will install via apt if missing)
- Ships with SQLite and DuckDB support; other databases need an extra
  adapter package (see the summary printed after install)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
REQ_VER="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- ensure python3 ----
export DEBIAN_FRONTEND=noninteractive
if ! command -v python3 &>/dev/null; then
  echo "📦 Installing python3 ..."
  apt-get update
  apt-get install -y --no-install-recommends python3 python3-pip python3-venv
  rm -rf /var/lib/apt/lists/*
else
  # Ensure venv module is available
  if ! python3 -m venv --help &>/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends python3-venv
    rm -rf /var/lib/apt/lists/*
  fi
fi

# ---- create venv and install ----
VENV_DIR="/opt/harlequin"
echo "🛠  Creating venv at ${VENV_DIR} ..."
python3 -m venv "$VENV_DIR"

if [[ "$REQ_VER" == "latest" ]]; then
  echo "⬇️  Installing latest Harlequin ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir harlequin
else
  echo "⬇️  Installing Harlequin ${REQ_VER} ..."
  "$VENV_DIR/bin/pip" install --no-cache-dir "harlequin==${REQ_VER}"
fi

# ---- symlink binaries ----
# hsql ships in the same package: a non-interactive "run this SQL and exit"
# companion (like `psql -c`), for scripts and CI that shouldn't need a TTY.
echo "🔗 Creating symlinks in /usr/local/bin ..."
ln -sf "$VENV_DIR/bin/harlequin" /usr/local/bin/harlequin
ln -sf "$VENV_DIR/bin/hsql" /usr/local/bin/hsql

# ---- friendly summary ----
echo "✅ Harlequin installed."
echo -n "   harlequin → "; harlequin --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Open a local file: harlequin mydata.db          # SQLite
- Open a DuckDB file: harlequin -a duckdb mydata.duckdb
- In-memory DuckDB:   harlequin
- Non-interactive:    hsql -c "select 1"           # no TTY needed

Notes:
- Harlequin's own install only ships SQLite and DuckDB support. Postgres and
  MySQL need an extra adapter installed into the same venv (root-owned, so
  this needs sudo), e.g.:
    sudo /opt/harlequin/bin/pip install harlequin-postgres
    sudo /opt/harlequin/bin/pip install harlequin-mysql
  then, if this booth also has CodingBooth's PostgreSQL or MySQL setup (both
  default to host localhost, user "$(whoami)", no password, default port —
  neither creates a database matching that user, so -d must name one that
  actually exists; PostgreSQL always has "postgres"):
    harlequin -a postgres -h localhost -U coder -d postgres
    harlequin -a mysql -h localhost -U coder
- See: https://harlequin.sh/
EON
