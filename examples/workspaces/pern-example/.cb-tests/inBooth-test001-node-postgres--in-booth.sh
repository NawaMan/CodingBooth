#!/bin/bash
set -euo pipefail
# Node.js 22 and the PostgreSQL client are installed.
echo "=== Testing Node.js and PostgreSQL ==="
node --version | grep -q '^v22'
npm --version
psql --version
command -v pg_ctl || ls /usr/lib/postgresql/*/bin/pg_ctl
