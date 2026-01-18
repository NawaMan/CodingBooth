#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Deletes the KinD cluster.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kind}"

echo "Deleting KinD cluster: $CLUSTER_NAME"
kind delete cluster --name "$CLUSTER_NAME"
echo "Cluster '$CLUSTER_NAME' deleted."
