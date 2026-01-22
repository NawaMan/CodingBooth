#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Starts port-forward to access the TODO app from the host.
# Uses --address 0.0.0.0 so the app is accessible through the DinD sidecar's port mapping.

set -euo pipefail

NAMESPACE="${NAMESPACE:-todo-app}"

echo "Starting port-forward for TODO app..."
echo "  Web UI:  http://localhost:3000"
echo "  API:     http://localhost:8080"
echo "  Export:  http://localhost:8081"
echo ""

# Kill any existing port-forwards for these ports
pkill -f "port-forward.*svc/web.*3000" 2>/dev/null || true
pkill -f "port-forward.*svc/api.*8080" 2>/dev/null || true
pkill -f "port-forward.*svc/export.*8081" 2>/dev/null || true

sleep 1

# Start port-forwards with --address 0.0.0.0 to bind to all interfaces
# This is required for access from host through DinD sidecar
kubectl port-forward svc/web 3000:80 -n "$NAMESPACE" --address 0.0.0.0 &
kubectl port-forward svc/api 8080:8080 -n "$NAMESPACE" --address 0.0.0.0 &
kubectl port-forward svc/export 8081:8081 -n "$NAMESPACE" --address 0.0.0.0 &

sleep 2

echo ""
echo "Port-forwards started in background."
echo "Run './access-app-stop.sh' to stop them."
