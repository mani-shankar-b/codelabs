kubectl patch deployment odigos-instrumentor -n odigosv2 --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "CK_ENDPOINT",
      "value": "https://your-nexus-server.com"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "CK_NEXUS_ENDPOINT",
      "value": "https://backup-server.com"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "CK_CLUSTER_NAME",
      "value": "my-cluster"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "CK_KARMAKIT_EVENTS_TEST_MODE",
      "value": "true"
    }
  }
]'


kubectl create secret generic telemetry-secret \
  --from-literal=api-key=your-secret-api-key-here \
  -n odigosv2


kubectl patch deployment odigos-instrumentor -n odigosv2 --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "CK_API_KEY", "valueFrom": {"secretKeyRef": {"name": "telemetry-secret", "key": "api-key"}}}}]'  
