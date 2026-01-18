#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Checks if the HTTP server is running.
# Displays green checkmark if running, red X if not.

PID_FILE="/tmp/js-server.pid"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if [[ -f "$PID_FILE" ]]; then
    PID="$(cat "$PID_FILE")"
    if kill -0 "$PID" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Server is running (PID: $PID)"
        exit 0
    fi
fi

echo -e "${RED}✗${NC} Server is not running"
exit 0
