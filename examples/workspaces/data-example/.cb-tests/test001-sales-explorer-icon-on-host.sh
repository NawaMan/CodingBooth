#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# The Sales Explorer dashboard is started by its desktop icon, not at boot.
#
# Four things have to hold together for that to be true, and all four break
# silently — a booth that boots fine still leaves you with an icon that does
# nothing:
#
#   1. the launcher is on the desktop            (cb-desktop-icon.sh ran)
#   2. its descriptor carries the start command  (cb-web-open can start it)
#   3. nothing listens on 13000 at boot          (the autostart really is gone)
#   4. the start command serves seeded rows      (build + start + DB all wired)
#
# One booth, one shell, all four — the booth is the expensive part.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../../.."
if [ -x "$REPO_ROOT/codingbooth" ]; then
    BOOTH="$REPO_ROOT/codingbooth"
else
    BOOTH="$REPO_ROOT/booth"
fi

# Pin a base image that exists. A dev or rc binary tags BOOTH_VERSION_TAG as
# e.g. 0.72.0--rc1, and rc variants are not published — the build then dies on
# "not found" long before it can say anything about this example. Prefer the
# newest released desktop-xfce image already on this machine, else pull latest.
BOOTH_VERSION="${CB_BOOTH_VERSION:-}"
if [ -z "$BOOTH_VERSION" ]; then
    BOOTH_VERSION="$(docker images --format '{{.Tag}}' nawaman/codingbooth 2>/dev/null \
        | sed -n 's/^desktop-xfce-//p' | grep -v -- '--rc' | sort -V | tail -1)"
fi
[ -n "$BOOTH_VERSION" ] || BOOTH_VERSION=latest

echo "=== Testing the Sales Explorer desktop icon (data example) ==="
echo "    base image: nawaman/codingbooth:desktop-xfce-${BOOTH_VERSION}"
echo ""

# Everything runs in one booth. The `!` guards are there because the whole
# script runs under `set -e` inside the booth too: a curl against a port that
# is *meant* to be dead must not end the run.
output=$("$BOOTH" --version "$BOOTH_VERSION" --port "${CB_PORT:-50711}" -- '
    if [ -f "$HOME/Desktop/sales-explorer-web.desktop" ]; then
        echo "ICON_ON_DESKTOP=yes"
    else
        echo "ICON_ON_DESKTOP=no"
    fi

    grep -h "^START_CMD=" /etc/cb-web-services/sales-explorer.conf 2>/dev/null \
        || echo "START_CMD=<no descriptor>"

    # A single curl here is worthless: a restored autostart spawns the server
    # and returns, so this line runs while node is still binding, and the
    # connection refusal reads exactly like "nothing was ever started". Watch
    # the port for long enough that a boot-time server would have surfaced --
    # only silence for the whole window means the autostart is really gone.
    port_at_boot=closed
    for _ in $(seq 1 15); do
        if curl -sS -o /dev/null --max-time 2 http://localhost:13000/ 2>/dev/null; then
            port_at_boot=serving
            break
        fi
        sleep 1
    done
    echo "PORT_AT_BOOT=$port_at_boot"

    start-sales-explorer >/dev/null 2>&1 || echo "STARTER_FAILED=yes"
    for _ in $(seq 1 30); do
        curl -sS -o /dev/null --max-time 2 http://localhost:13000/ 2>/dev/null && break
        sleep 1
    done

    echo "AFTER_START=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:13000/ 2>/dev/null || echo 000)"
    echo "SALES_ROWS=$(curl -sS --max-time 10 http://localhost:13000/api/sales 2>/dev/null | grep -o "\"id\":" | wc -l)"
' 2>&1) || true

echo "$output"
echo ""

failed=0

check() {  # check <label> <expected-line> <what-it-means>
    if grep -qxF "$2" <<< "$output"; then
        echo -e "${GREEN}\xe2\x9c\x93${NC} $1"
    else
        echo -e "${RED}\xe2\x9c\x97${NC} $1 — expected '$2'"
        failed=1
    fi
}

check "Icon is on the desktop"                 "ICON_ON_DESKTOP=yes"
check "Descriptor carries the start command"   "START_CMD=start-sales-explorer"
check "Nothing listens on 13000 at boot"       "PORT_AT_BOOT=closed"
check "Dashboard answers after the start"      "AFTER_START=200"

# The row count proves the dashboard reached the seeded database, not just that
# something is listening: an Express error page would still be a 200.
rows=$(sed -n 's/^SALES_ROWS=//p' <<< "$output" | tail -1)
if [ "${rows:-0}" -gt 0 ] 2>/dev/null; then
    echo -e "${GREEN}\xe2\x9c\x93${NC} /api/sales returned $rows seeded rows"
else
    echo -e "${RED}\xe2\x9c\x97${NC} /api/sales returned no rows (got '${rows:-}')"
    failed=1
fi

echo ""
if [ $failed -eq 0 ]; then
    echo -e "${GREEN}Sales Explorer icon test passed!${NC}"
else
    echo -e "${RED}Sales Explorer icon test FAILED!${NC}"
    exit 1
fi
