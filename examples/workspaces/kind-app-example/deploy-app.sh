#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="todo-app"
KIND_CLUSTER_NAME="kind"

echo "=== Deploying TODO App to KIND ==="

# Check if KIND cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    echo "Error: KIND cluster '${KIND_CLUSTER_NAME}' not found."
    echo "Please create a KIND cluster first with: kind create cluster"
    exit 1
fi

# Set kubectl context to KIND
kubectl cluster-info --context kind-${KIND_CLUSTER_NAME} > /dev/null 2>&1 || {
    echo "Error: Cannot connect to KIND cluster"
    exit 1
}

echo ""
echo ">>> Loading images into KIND cluster..."
kind load docker-image todo-api:latest --name ${KIND_CLUSTER_NAME}
kind load docker-image todo-export:latest --name ${KIND_CLUSTER_NAME}
kind load docker-image todo-web:latest --name ${KIND_CLUSTER_NAME}

echo ""
echo ">>> Creating namespace '${NAMESPACE}'..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo ">>> Applying Kubernetes manifests..."

# Apply in order: ConfigMaps/Secrets -> PVCs -> Deployments -> Services
kubectl apply -f k8s/postgres-pvc.yaml -n ${NAMESPACE}
kubectl apply -f k8s/postgres-configmap.yaml -n ${NAMESPACE}
kubectl apply -f k8s/postgres-deployment.yaml -n ${NAMESPACE}
kubectl apply -f k8s/postgres-service.yaml -n ${NAMESPACE}

echo ""
echo ">>> Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/postgres -n ${NAMESPACE}

# Apply app services
kubectl apply -f k8s/export-deployment.yaml -n ${NAMESPACE}
kubectl apply -f k8s/export-service.yaml -n ${NAMESPACE}

kubectl apply -f k8s/api-configmap.yaml -n ${NAMESPACE}
kubectl apply -f k8s/api-deployment.yaml -n ${NAMESPACE}
kubectl apply -f k8s/api-service.yaml -n ${NAMESPACE}

kubectl apply -f k8s/web-configmap.yaml -n ${NAMESPACE}
kubectl apply -f k8s/web-deployment.yaml -n ${NAMESPACE}
kubectl apply -f k8s/web-service.yaml -n ${NAMESPACE}

echo ""
echo ">>> Waiting for all deployments to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/export-service -n ${NAMESPACE}
kubectl wait --for=condition=available --timeout=120s deployment/api -n ${NAMESPACE}
kubectl wait --for=condition=available --timeout=120s deployment/web -n ${NAMESPACE}

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Services:"
kubectl get svc -n ${NAMESPACE}

echo ""
echo "Pods:"
kubectl get pods -n ${NAMESPACE}

echo ""
echo ">>> To access the application, run:"
echo "    kubectl port-forward svc/web 3000:80 -n ${NAMESPACE}"
echo ""
echo ">>> Then open http://localhost:3000 in your browser"
