kubectl patch deployment odigos-ui -n odigosv2 --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CK_OTEL_METRICS_ENABLED","value":"true"}},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CK_METRICS_ENDPOINT","value":"http://ck-intel-collector-opentelemetry-collector.default.svc.cluster.local:4319"}},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CK_METRICS_PROTOCOL","value":"grpc"}},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CK_OTEL_METRICS_INTERVAL","value":"10s"}},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CK_STATUS_REPORT_ENABLED","value":"true"}},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CK_STATUS_REPORT_INTERVAL","value":"1m"}}
]'
