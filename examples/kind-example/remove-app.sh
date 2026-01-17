#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Removes the nginx app from the KinD cluster.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kind}"

echo "Removing nginx from cluster '$CLUSTER_NAME'..."
kubectl --context "kind-$CLUSTER_NAME" delete deployment nginx --ignore-not-found
kubectl --context "kind-$CLUSTER_NAME" delete service nginx --ignore-not-found
echo "App removed."
