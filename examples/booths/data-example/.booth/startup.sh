#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ============================================================================
# Data Example — startup
#
# Runs at container startup, after the system hooks. It waits for PostgreSQL,
# creates the `demo` database, and seeds the sales table (idempotent — safe to
# run every start).
#
# The Sales Explorer dashboard is deliberately NOT started here: its desktop
# icon builds and starts it on demand (see .booth/setups/sales-explorer-icon--setup.sh).
#
# The Jupyter notebook is auto-started separately by the generated
# startups/65-notebook-autostart--startup.sh hook.
# ============================================================================

set -euo pipefail

SALES_DIR="$HOME/code/sales-explorer"

if [[ "${CB_SILENCE_BUILD:-false}" != "true" ]]; then
  echo "🗄️  Seeding the demo database..."
fi

if [ -f "$SALES_DIR/init-demo-db.sql" ]; then
  # Wait for PostgreSQL to accept connections (its own startup hook runs earlier).
  for _ in $(seq 1 30); do
    pg_isready -q 2>/dev/null && break
    sleep 1
  done

  # Create the demo database if it does not already exist.
  if ! psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw demo; then
    createdb demo 2>/dev/null || true
  fi

  # Seed the sales table (the SQL only inserts when the table is empty).
  psql -d demo -f "$SALES_DIR/init-demo-db.sql" 2>/dev/null || true
fi

if [[ "${CB_SILENCE_BUILD:-false}" != "true" ]]; then
  echo "✅ Data example ready — DBeaver and JupyterLab are wired to the 'demo' database."
  echo "   Sales Explorer: click its desktop icon (or run start-sales-explorer) to build and start it."
fi
