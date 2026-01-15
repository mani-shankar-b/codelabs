# Simple Go In-Memory App

A simple Go REST API application with in-memory data storage, designed to be deployed to a Kind cluster with Odigos observability.

## Features

- REST API with in-memory data storage
- Health check endpoint
- CRUD operations for items
- Thread-safe operations using mutexes
- Ready for Odigos auto-instrumentation

## API Endpoints

- `GET /health` - Health check
- `GET /items` - Get all items
- `GET /items/{id}` - Get item by ID
- `POST /api/items` - Create new item
- `PUT /api/items/{id}` - Update item
- `DELETE /api/items/{id}` - Delete item

## Quick Start

### Prerequisites

- Docker
- Kind cluster running
- kubectl configured
- Odigos installed in the cluster (optional, for observability)

### Deploy to Kind

```bash
cd demo/apps/simple-go-app
./deploy.sh
```

### Manual Deployment

```bash
# Build image
docker build -t simple-go-app:latest .

# Load into Kind
kind load docker-image simple-go-app:latest --name=kind

# Deploy
kubectl apply -f deployment.yaml

# Check status
kubectl get pods -l app=simple-go-app
kubectl get svc simple-go-app
```

### Test the Application

```bash
# Port-forward
kubectl port-forward -n default svc/simple-go-app 8080:8080

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/items
curl http://localhost:8080/items/1

# Create item
curl -X POST http://localhost:8080/api/items \
  -H "Content-Type: application/json" \
  -d '{"name": "New Item", "value": 400}'
```

## Odigos Integration

This application is ready for Odigos auto-instrumentation. Odigos will automatically:

- Detect the Go application
- Add OpenTelemetry instrumentation
- Collect traces, metrics, and logs
- Export to configured backends

No code changes are required - Odigos handles instrumentation automatically.

## Local Development

```bash
# Run locally
go run main.go

# Test locally
curl http://localhost:8080/health
curl http://localhost:8080/items
```

## Cleanup

```bash
kubectl delete -f deployment.yaml
```

