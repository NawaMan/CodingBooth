#!/bin/bash
set -e

NAMESPACE="todo-app"
KIND_CLUSTER_NAME="kind"

echo "=== Removing TODO App from KIND ==="

# Check if KIND cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    echo "KIND cluster '${KIND_CLUSTER_NAME}' not found. Nothing to remove."
    exit 0
fi

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} > /dev/null 2>&1; then
    echo "Namespace '${NAMESPACE}' not found. Nothing to remove."
    exit 0
fi

echo ""
echo ">>> Deleting all resources in namespace '${NAMESPACE}'..."

# Delete in reverse order
kubectl delete -f k8s/web-service.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/web-deployment.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/web-configmap.yaml -n ${NAMESPACE} --ignore-not-found

kubectl delete -f k8s/api-service.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/api-deployment.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/api-configmap.yaml -n ${NAMESPACE} --ignore-not-found

kubectl delete -f k8s/export-service.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/export-deployment.yaml -n ${NAMESPACE} --ignore-not-found

kubectl delete -f k8s/postgres-service.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/postgres-deployment.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/postgres-configmap.yaml -n ${NAMESPACE} --ignore-not-found
kubectl delete -f k8s/postgres-pvc.yaml -n ${NAMESPACE} --ignore-not-found

echo ""
echo ">>> Deleting namespace '${NAMESPACE}'..."
kubectl delete namespace ${NAMESPACE} --ignore-not-found

echo ""
echo "=== TODO App removed successfully ==="
