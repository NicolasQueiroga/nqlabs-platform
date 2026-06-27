# Layer 3 Observability

Layer 3 gives the platform a mature application telemetry baseline: metrics,
logs, traces, profiles, synthetic probes, alerting, and long-term metrics.

## Metrics architecture

- Management runs kube-prometheus-stack for local scraping, dashboards, and alerts.
- Staging and production run kube-prometheus-stack in **agent mode shape**:
  Prometheus Operator + kube-state-metrics + node-exporter, plus a
  `PrometheusAgent` CR.
- Remote `PrometheusAgent` instances scrape all ServiceMonitors, PodMonitors,
  Probes, and ScrapeConfigs in their cluster and remote_write to:

```text
http://thanos-receive.platform.nqlabs.network:31991/api/v1/receive
```

Remote clusters resolve the exact `thanos-receive.platform.nqlabs.network` name
to the management node (`192.168.15.31`) and use a pinned Thanos Receive NodePort
because remote pod egress can reach the management node IP but not the management
Cilium Gateway LoadBalancer IP. This endpoint is private LAN machine-to-machine
telemetry, not public exposure.

- Management Prometheus also remote_writes to in-cluster Thanos Receive:

```text
http://thanos-receive.monitoring.svc.cluster.local:19291/api/v1/receive
```

- Thanos components in management:
  - Query + Query Frontend
  - Receive
  - Store Gateway
  - Compactor
  - Bucket Web
- Object storage: Ceph RGW bucket `thanos`.
- Retention:
  - Prometheus local: 7d fast operational window
  - Thanos raw: 30d
  - Thanos 5m: 90d
  - Thanos 1h: 365d

## Tracing

Tempo is the central trace backend. Each cluster has an `otel-collector` service:

```text
otel-collector.monitoring.svc.cluster.local:4317  # OTLP/gRPC
otel-collector.monitoring.svc.cluster.local:4318  # OTLP/HTTP
```

Remote collectors forward OTLP/HTTP to the private management route:

```text
http://otel.platform.nqlabs.network:31418
```

Remote clusters resolve exact `otel.platform.nqlabs.network` to the management
node and use the pinned OTel Collector NodePort for the same private LAN reason
as remote metrics remote_write.

Applications should prefer local in-cluster collector endpoints and let the
platform forward cross-cluster traffic.

## Profiling

Pyroscope is the central profiling backend:

```text
http://pyroscope.monitoring.svc.cluster.local:4040
https://pyroscope.platform.nqlabs.network
```

For services that support Pyroscope push mode, configure the Pyroscope server URL
through service-factory values/secrets rather than hardcoding it. Pyroscope UI is
behind Authentik.

## Logs

- Promtail ships Kubernetes pod logs to Loki.
- Falco JSON logs are parsed into labels:
  - `falco_priority`
  - `falco_rule`
  - `falco_source`
- Loki has a ServiceMonitor and alert rules.
- Loki is single-binary with filesystem storage; Velero protects the PVC.

## Synthetic monitoring

Blackbox exporter probes:

- Internal service health
- Edge OIDC pages
- Edge Authentik redirects
- DNS resolution
- TCP connectivity
- Staging and production demo routes

Gatus provides human-readable status and is scraped by Prometheus.

## Application contract

A mature application should expose:

- `/metrics` for Prometheus ServiceMonitor scraping
- OTLP traces to local `otel-collector`
- structured JSON logs
- optional Pyroscope profiles
- health endpoints for Gatus/blackbox

Recommended env vars for apps:

```text
OTEL_SERVICE_NAME=<app>
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=<env>,service.namespace=<namespace>
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.monitoring.svc.cluster.local:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
PYROSCOPE_SERVER_ADDRESS=http://pyroscope.monitoring.svc.cluster.local:4040
```

Remote apps should not write directly to management backends unless the local
collector is unavailable or an app cannot use a collector.

Pyroscope currently runs as root for the same Talos/local-path subPath reason as
Prometheus and Alertmanager: its metastore mounts a subPath from the PVC and
non-root writes fail at the kernel bind-mount layer. Keep this scoped to the
privileged `monitoring` namespace and revisit when storage moves off local-path.

## Verification

Strict Argo verification must check all three:

```text
sync.status == Synced
health.status == Healthy
operationState.phase == Succeeded or no failed operation
```

Do not declare Layer 3 green from sync/health alone.
