#!/usr/bin/env bash

URL="http://localhost:8080"
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

# Get HTTP status (000 if unreachable)
status_code=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

green="\e[32m"
red="\e[31m"
reset="\e[0m"

if [[ "$EXPECT" == "up" ]]; then
  if [[ "$status_code" == "200" ]]; then
    echo -e "${green}✔ SUCCESS: $URL is UP (200)${reset}"
    exit 0
  else
    echo -e "${red}✖ FAILURE: $URL expected UP, got $status_code${reset}"
    exit 1
  fi
else # expect down
  if [[ "$status_code" != "200" ]]; then
    echo -e "${green}✔ SUCCESS: $URL is DOWN (got $status_code)${reset}"
    exit 0
  else
    echo -e "${red}✖ FAILURE: $URL expected DOWN, but is UP (200)${reset}"
    exit 1
  fi
fi
