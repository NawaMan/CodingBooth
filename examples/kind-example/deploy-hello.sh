#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Builds and deploys the hello-service to the KinD cluster.

set -euo pipefail

cd "$(dirname "$0")"

CLUSTER_NAME="${CLUSTER_NAME:-kind}"
DIND_NAME="${WS_CONTAINER_NAME}-${WS_HOST_PORT}-dind"

echo "Building hello-service image..."
docker build -t hello-service:local ./app

echo
echo "Loading image into KinD cluster..."
kind load docker-image hello-service:local --name "$CLUSTER_NAME"

echo
echo "Deploying hello-service..."
kubectl --context "kind-$CLUSTER_NAME" apply -f ./app/k8s.yaml

echo
echo "Waiting for deployment to be ready..."
kubectl --context "kind-$CLUSTER_NAME" rollout status deployment/hello-service --timeout=60s

echo
echo "Deployment complete!"
kubectl --context "kind-$CLUSTER_NAME" get pods,svc -l app=hello-service

echo
echo "Test the service:"
echo "  curl http://${DIND_NAME}:30081"
echo "  curl http://${DIND_NAME}:30081/health"
