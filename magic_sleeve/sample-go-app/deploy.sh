#!/bin/bash

# Deploy Simple Go App to Kind Cluster
set -e

APP_NAME="simple-go-app"
IMAGE_NAME="${APP_NAME}:latest"
KIND_CLUSTER_NAME="kind"

echo "🚀 Building and deploying ${APP_NAME} to Kind cluster..."

# Build the Docker image
echo "📦 Building Docker image..."
docker build -t ${IMAGE_NAME} .

# Load image into Kind cluster
echo "📥 Loading image into Kind cluster..."
kind load docker-image ${IMAGE_NAME} --name=${KIND_CLUSTER_NAME}

# Deploy to Kubernetes
echo "☸️  Deploying to Kubernetes..."
kubectl apply -f deployment.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/${APP_NAME} -n default

# Get service info
echo ""
echo "✅ Deployment complete!"
echo ""
echo "Service information:"
kubectl get svc ${APP_NAME} -n default
echo ""
echo "Pod information:"
kubectl get pods -l app=${APP_NAME} -n default
echo ""
echo "To port-forward and test:"
echo "  kubectl port-forward -n default svc/${APP_NAME} 8080:8080"
echo ""
echo "Then test with:"
echo "  curl http://localhost:8080/health"
echo "  curl http://localhost:8080/items"
echo ""

