#!/bin/bash

# Configuration
APP_NAME="sample-python-app"
IMAGE_NAME="$APP_NAME:latest"
NAMESPACE="demo-ns"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Get the kind cluster name
echo "Finding kind cluster..."
cluster=$(kind get clusters | head -n 1)

if [ -z "$cluster" ]; then
    echo "Error: No kind cluster found."
    exit 1
fi

echo "Using kind cluster: $cluster"

# 1. Build the Docker image
echo "Building Docker image $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" "$DIR"

# 2. Load the image into the kind cluster
echo "Loading image into kind cluster $cluster..."
kind load docker-image "$IMAGE_NAME" --name "$cluster"

# 3. Apply the manifests
echo "Applying Kubernetes manifests to namespace $NAMESPACE..."
kubectl apply -f "$DIR/deployment.yaml"

echo "Deployment complete! Deployment status:"
kubectl get pods -n "$NAMESPACE" -l app="$APP_NAME"
