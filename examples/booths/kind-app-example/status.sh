#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Shows the status of the KIND cluster and TODO app.

CLUSTER_NAME="${CLUSTER_NAME:-kind}"
NAMESPACE="${NAMESPACE:-todo-app}"

green="\e[32m"
red="\e[31m"
yellow="\e[33m"
blue="\e[34m"
reset="\e[0m"

echo -e "${blue}=== KIND Cluster Status ===${reset}"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${green}✔ Cluster '$CLUSTER_NAME' is running${reset}"
    echo ""
    kubectl get nodes --context "kind-$CLUSTER_NAME" 2>/dev/null || true
else
    echo -e "${red}✖ Cluster '$CLUSTER_NAME' is not running${reset}"
    echo "  Run: ./start-cluster.sh"
    exit 0
fi

echo ""
echo -e "${blue}=== TODO App Pods ===${reset}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || echo "No pods found"
else
    echo -e "${yellow}⚠ Namespace '$NAMESPACE' does not exist${reset}"
    echo "  Run: ./deploy-app.sh"
fi

echo ""
echo -e "${blue}=== TODO App Services ===${reset}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    kubectl get svc -n "$NAMESPACE" 2>/dev/null || echo "No services found"
fi

echo ""
echo -e "${blue}=== Port-Forwards ===${reset}"
pf_web=$(pgrep -f "port-forward.*svc/web.*3000" 2>/dev/null || true)
pf_api=$(pgrep -f "port-forward.*svc/api.*8080" 2>/dev/null || true)
pf_export=$(pgrep -f "port-forward.*svc/export.*8081" 2>/dev/null || true)

if [[ -n "$pf_web" ]]; then
    echo -e "${green}✔ Web UI:    http://localhost:3000 (PID: $pf_web)${reset}"
else
    echo -e "${yellow}○ Web UI:    not forwarded${reset}"
fi

if [[ -n "$pf_api" ]]; then
    echo -e "${green}✔ API:       http://localhost:8080 (PID: $pf_api)${reset}"
else
    echo -e "${yellow}○ API:       not forwarded${reset}"
fi

if [[ -n "$pf_export" ]]; then
    echo -e "${green}✔ Export:    http://localhost:8081 (PID: $pf_export)${reset}"
else
    echo -e "${yellow}○ Export:    not forwarded${reset}"
fi

if [[ -z "$pf_web" && -z "$pf_api" && -z "$pf_export" ]]; then
    echo ""
    echo "  Run: ./access-app.sh"
fi
