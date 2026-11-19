#!/bin/bash
set -euo pipefail
# postgresql server and client binaries and postgrest are installed
echo "=== Testing PostgreSQL and PostgREST ==="
psql --version
command -v postgres >/dev/null || ls /usr/lib/postgresql/*/bin/postgres
postgrest --version | grep -qi postgrest
