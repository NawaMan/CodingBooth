#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Deploys a simple nginx app to the KinD cluster.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kind}"

echo "Deploying nginx to cluster '$CLUSTER_NAME'..."

kubectl --context "kind-$CLUSTER_NAME" apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
EOF

echo
echo "Waiting for deployment to be ready..."
kubectl --context "kind-$CLUSTER_NAME" rollout status deployment/nginx --timeout=60s

echo
echo "Deployment complete!"
kubectl --context "kind-$CLUSTER_NAME" get pods,svc
