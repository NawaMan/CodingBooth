#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Creates a KinD (Kubernetes in Docker) cluster.
# Configures the API server to be accessible from the workspace container via DinD.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kind}"
DIND_NAME="${CB_CONTAINER_NAME}-${CB_HOST_PORT}-dind"
API_PORT="${KIND_API_PORT:-6443}"

echo "Creating KinD cluster: $CLUSTER_NAME"
echo "DinD sidecar: $DIND_NAME"

# Create kind config that:
# 1. Binds API server to 0.0.0.0 (accessible from outside)
# 2. Adds DinD hostname to the certificate SANs
# 3. Maps NodePort range to DinD container interface
cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "0.0.0.0"
  apiServerPort: ${API_PORT}
nodes:
- role: control-plane
  extraPortMappings:
  # Map common NodePort range to host (DinD container)
  - containerPort: 30080
    hostPort: 30080
    listenAddress: "0.0.0.0"
    protocol: TCP
  - containerPort: 30081
    hostPort: 30081
    listenAddress: "0.0.0.0"
    protocol: TCP
  - containerPort: 30082
    hostPort: 30082
    listenAddress: "0.0.0.0"
    protocol: TCP
  - containerPort: 30083
    hostPort: 30083
    listenAddress: "0.0.0.0"
    protocol: TCP
  - containerPort: 30084
    hostPort: 30084
    listenAddress: "0.0.0.0"
    protocol: TCP
  # HTTP/HTTPS for ingress
  - containerPort: 80
    hostPort: 80
    listenAddress: "0.0.0.0"
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    listenAddress: "0.0.0.0"
    protocol: TCP
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      certSANs:
      - "${DIND_NAME}"
      - "localhost"
      - "127.0.0.1"
      - "0.0.0.0"
EOF

# Create cluster with the config
kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config.yaml --wait 60s

# Kubeconfig uses localhost which works because workspace shares DinD's network namespace
echo
echo "Cluster '$CLUSTER_NAME' is ready!"
echo "NodePorts 30080-30084, 80, 443 are accessible via: localhost"
echo
kubectl cluster-info --context "kind-$CLUSTER_NAME"
