#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Checks if the KinD cluster is running.

CLUSTER_NAME="${CLUSTER_NAME:-kind}"
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
reset="\e[0m"

# Check if cluster exists
cluster_exists=$(kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$" && echo "yes" || echo "no")

if [[ "$EXPECT" == "up" ]]; then
  if [[ "$cluster_exists" == "yes" ]]; then
    echo -e "${green}✔ SUCCESS: Cluster '$CLUSTER_NAME' is UP${reset}"
    kubectl get nodes --context "kind-$CLUSTER_NAME" 2>/dev/null || true
    exit 0
  else
    echo -e "${red}✖ FAILURE: Cluster '$CLUSTER_NAME' expected UP, but is DOWN${reset}"
    exit 1
  fi
else # expect down
  if [[ "$cluster_exists" == "no" ]]; then
    echo -e "${green}✔ SUCCESS: Cluster '$CLUSTER_NAME' is DOWN${reset}"
    exit 0
  else
    echo -e "${red}✖ FAILURE: Cluster '$CLUSTER_NAME' expected DOWN, but is UP${reset}"
    exit 1
  fi
fi
