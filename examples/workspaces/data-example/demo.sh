#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Check the data workbench from inside the booth, without the desktop. The booth
# starts PostgreSQL and .booth/startup.sh seeds the `demo` database on boot, so
# each command first waits (up to 60s) for the `sales` rows.
#   ./demo.sh sql   revenue by category, straight from PostgreSQL
#   ./demo.sh api   start the Sales Explorer server (start-sales-explorer) and
#                   ask its API for the same summary
set -euo pipefail

API=http://localhost:13000

# wait_for <description> <command...> — retry the command once a second for 60s.
wait_for() {
  local what="$1"; shift
  for _ in $(seq 60); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "Gave up after 60s waiting for ${what}." >&2
  exit 1
}

seeded() { [ "$(psql -d demo -tAc 'SELECT count(*) FROM sales')" -gt 0 ]; }

case "${1:-sql}" in
  sql)
    wait_for "the seeded sales table in the demo database" seeded
    psql -d demo -c "
      SELECT category,
             count(*)          AS sales,
             sum(quantity)     AS units,
             sum(total_amount) AS revenue
      FROM sales
      GROUP BY category
      ORDER BY revenue DESC"
    ;;
  api)
    wait_for "the seeded sales table in the demo database" seeded
    start-sales-explorer
    wait_for "Sales Explorer to answer on ${API}" curl -fsS -o /dev/null "${API}/api/filters"
    echo "GET ${API}/api/sales/summary"
    curl -fsS "${API}/api/sales/summary" | node -e '
      let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
        for (const r of JSON.parse(s))
          console.log(`  ${r.label.padEnd(12)} ${String(r.num_transactions).padStart(3)} sales  ${String(r.total_revenue).padStart(10)}`);
      });'
    ;;
  *)
    echo "usage: $0 sql|api" >&2
    exit 2
    ;;
esac
