# Grafana Dashboards

Place exported Grafana dashboard JSON files here and reference in values.yaml.

## Coming Soon
- Overview dashboard: global traffic, error rate, latency
- Control plane dashboard: reconciliation latency, xDS push frequency
- Data plane dashboard: request QPS, P99 latency, connections
- AI gateway dashboard: token usage, provider latency, rate limits

Enable via:
```yaml
observability:
  grafana:
    dashboards:
      enabled: true
```
