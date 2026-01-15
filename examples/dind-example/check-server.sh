#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Checks if the http-server container is running.
# Displays green checkmark if running, red X if not.

CONTAINER_NAME="http-server"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${GREEN}✓${NC} Server is running"
else
    echo -e "${RED}✗${NC} Server is not running"
fi
