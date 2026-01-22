#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Image names
API_IMAGE="todo-api:latest"
EXPORT_IMAGE="todo-export:latest"
WEB_IMAGE="todo-web:latest"

echo "=== Building TODO App Docker Images ==="

# Build API service
echo ""
echo ">>> Building API service..."
docker build -t "$API_IMAGE" ./api

# Build Export service
echo ""
echo ">>> Building Export service..."
docker build -t "$EXPORT_IMAGE" ./export-service

# Build Web frontend
echo ""
echo ">>> Building Web frontend..."
docker build -t "$WEB_IMAGE" ./web

echo ""
echo "=== All images built successfully ==="
echo ""
echo "Images:"
docker images | grep -E "todo-(api|export|web)" || true
