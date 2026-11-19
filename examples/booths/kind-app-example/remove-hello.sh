#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Removes the hello-service from the KinD cluster.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kind}"

echo "Removing hello-service..."
kubectl --context "kind-$CLUSTER_NAME" delete -f ./app/k8s.yaml --ignore-not-found
echo "Service removed."
