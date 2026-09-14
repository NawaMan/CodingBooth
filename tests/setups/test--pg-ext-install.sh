#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: pg-ext--install.sh extension-name to apt-package resolution
#
# Runs the real pg-ext--install.sh with `pg_config` and `apt-get` stubbed, and
# asserts what it hands to apt-get and what it records for the startup step
# (which enables extensions with CREATE EXTENSION once the server is up).
#
# The interesting cases: several contrib-bundled extension names must all
# collapse into a single `postgresql-contrib` apt-get call (not one per name,
# and not omitted), an unversioned/unknown name must fail the build rather
# than guess a package that may not exist, and the manifest must record the
# extension *names* pg-ext-pkg was given, not the apt package names.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PG_EXT_SCRIPT="$REPO_ROOT/variants/base/setups/pg-ext--install.sh"

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/conf"

cat > "$STUB/bin/pg_config" << 'EOF'
#!/bin/bash
[[ "$1" == "--version" ]] && echo "PostgreSQL 16.4"
EOF
chmod +x "$STUB/bin/pg_config"

# Stub apt-get: echoes its argv (both `update` and `install ...` calls land here).
cat > "$STUB/bin/apt-get" << 'EOF'
#!/bin/bash
echo "STUB_APT_GET $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/bin/apt-get"

run_pg_ext_install() {
    rm -f "$STUB_LOG" 2>/dev/null || true
    rm -rf "$STUB/conf" && mkdir -p "$STUB/conf"
    PATH="$STUB/bin:$PATH" STUB_LOG="$STUB/log" CB_PG_CONF_DIR="$STUB/conf" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$PG_EXT_SCRIPT" "$@" 2>&1
}
STUB_LOG="$STUB/log"

ALL_PASSED=true

# 1. Single extension: resolves to its own versioned package, and the manifest
# records the same name (package name and CREATE EXTENSION name agree here).
out=$(run_pg_ext_install postgis) || { ALL_PASSED=false; }
if grep -qF "STUB_APT_GET install" "$STUB/log" && grep -qF "postgresql-16-postgis-3" "$STUB/log" \
   && [[ "$(cat "$STUB/conf/extensions.list")" == "postgis" ]]; then
    print_test_result "true" "$0" "1" "single extension resolves to its versioned package and is recorded by name"
else
    print_test_result "false" "$0" "1" "single extension resolves to its versioned package and is recorded by name"
    echo "  actual apt-get log: $(cat "$STUB/log" 2>/dev/null)"
    echo "  actual manifest:    $(cat "$STUB/conf/extensions.list" 2>/dev/null)"
    ALL_PASSED=false
fi

# 1b. pgvector is the one case where the apt package name and the CREATE
# EXTENSION identifier disagree: the package is postgresql-<ver>-pgvector, but
# it ships vector.control, so `CREATE EXTENSION pgvector` would fail with
# "extension \"pgvector\" is not available" against a correctly installed
# package. The manifest must record "vector", not "pgvector".
out=$(run_pg_ext_install pgvector) || { ALL_PASSED=false; }
if grep -qF "postgresql-16-pgvector" "$STUB/log" \
   && [[ "$(cat "$STUB/conf/extensions.list")" == "vector" ]]; then
    print_test_result "true" "$0" "1b" "pgvector installs the pgvector package but records the CREATE EXTENSION name 'vector'"
else
    print_test_result "false" "$0" "1b" "pgvector installs the pgvector package but records the CREATE EXTENSION name 'vector'"
    echo "  actual apt-get log: $(cat "$STUB/log" 2>/dev/null)"
    echo "  actual manifest:    $(cat "$STUB/conf/extensions.list" 2>/dev/null)"
    ALL_PASSED=false
fi

# 2. Two contrib-bundled names dedup to a single postgresql-contrib install.
out=$(run_pg_ext_install pg_trgm hstore) || { ALL_PASSED=false; }
install_calls=$(grep -c "STUB_APT_GET install" "$STUB/log" || true)
contrib_count=$(grep -o "postgresql-contrib" "$STUB/log" | wc -l | tr -d ' ')
if [[ "$install_calls" == "1" ]] && [[ "$contrib_count" == "1" ]] \
   && [[ "$(cat "$STUB/conf/extensions.list")" == $'pg_trgm\nhstore' ]]; then
    print_test_result "true" "$0" "2" "two contrib-bundled extensions dedup to one postgresql-contrib install"
else
    print_test_result "false" "$0" "2" "two contrib-bundled extensions dedup to one postgresql-contrib install"
    echo "  install calls: $install_calls, postgresql-contrib occurrences: $contrib_count"
    echo "  actual apt-get log: $(cat "$STUB/log" 2>/dev/null)"
    echo "  actual manifest:    $(cat "$STUB/conf/extensions.list" 2>/dev/null)"
    ALL_PASSED=false
fi

# 3. An unknown extension name fails the build rather than guessing a package.
if out=$(run_pg_ext_install not-a-real-extension 2>&1); then
    print_test_result "false" "$0" "3" "unknown extension name fails the build"
    echo "  expected non-zero exit; script succeeded with: $out"
    ALL_PASSED=false
elif echo "$out" | grep -q "Unknown PostgreSQL extension"; then
    print_test_result "true" "$0" "3" "unknown extension name fails the build"
else
    print_test_result "false" "$0" "3" "unknown extension name fails the build"
    echo "  actual: $out"
    ALL_PASSED=false
fi

# 4. No extensions requested is a no-op, not a failure (empty PG_EXTS default).
if run_pg_ext_install "" | grep -q "No PostgreSQL extensions requested"; then
    print_test_result "true" "$0" "4" "empty extension list is a no-op"
else
    print_test_result "false" "$0" "4" "empty extension list is a no-op"
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
