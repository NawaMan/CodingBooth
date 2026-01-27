#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Checks if API and Vite dev servers are running (--expect=up) or stopped (--expect=down).
# Server ports to check
API_PORT=${API_PORT:-3000}
VITE_PORT=${VITE_PORT:-5173}

EXPECT="up"

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --expect=up)
      EXPECT="up"
      ;;
    --expect=down)
      EXPECT="down"
      ;;
    *)
      echo "Usage: $0 [--expect=up|--expect=down]"
      exit 2
      ;;
  esac
done

green="\e[32m"
red="\e[31m"
yellow="\e[33m"
reset="\e[0m"

# Function to check a single server
check_server() {
  local name="$1"
  local port="$2"
  local url="http://localhost:$port"
  
  # Get HTTP status (000 if unreachable)
  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" --max-time 2)
  
  if [[ "$EXPECT" == "up" ]]; then
    if [[ "$status_code" == "200" ]]; then
      echo -e "${green}✔ $name (port $port): UP (200)${reset}"
      return 0
    else
      echo -e "${red}✖ $name (port $port): expected UP, got $status_code${reset}"
      return 1
    fi
  else # expect down
    if [[ "$status_code" != "200" ]]; then
      echo -e "${green}✔ $name (port $port): DOWN ($status_code)${reset}"
      return 0
    else
      echo -e "${red}✖ $name (port $port): expected DOWN, but is UP (200)${reset}"
      return 1
    fi
  fi
}

echo "Checking servers (expecting: $EXPECT)..."
echo ""

FAILURES=0

# Check all three servers
check_server "API server"      "$API_PORT"  || ((FAILURES++))
check_server "Vite dev server" "$VITE_PORT" || ((FAILURES++))

echo ""

if [[ $FAILURES -eq 0 ]]; then
  echo -e "${green}All servers match expected state ($EXPECT)${reset}"
  exit 0
else
  echo -e "${red}$FAILURES server(s) did not match expected state${reset}"
  exit 1
fi
