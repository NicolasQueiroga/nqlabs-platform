# Runbook: Monitoring Stack

## Overview

The monitoring stack is deployed by ArgoCD using kube-prometheus-stack.

Layer 3 observability architecture (remote Prometheus Agent, Thanos, Tempo,
Pyroscope, OTel Collector, and application telemetry contract) is documented in
[`observability-layer-3.md`](./observability-layer-3.md).

| Component | URL |
|-----------|-----|
| Grafana | `https://grafana.platform.nqlabs.network` |
| Prometheus | `https://prometheus.platform.nqlabs.network` |
| Alertmanager | `https://alertmanager.platform.nqlabs.network` |
| Hubble UI | `https://hubble.platform.nqlabs.network` |

ArgoCD apps:

| App | Purpose |
|-----|---------|
| `monitoring-config` | ExternalSecret for Grafana credentials + HTTPRoutes |
| `kube-prometheus-stack` | Helm chart: Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter |
| `blackbox-exporter` | HTTP/TLS endpoint probing for platform and demo service URLs |
| `loki` | Single-binary Loki log store with local-path persistence |
| `promtail` | DaemonSet log shipper for Kubernetes pod/container logs |

Hubble metrics come from Cilium's `hubble-metrics` ServiceMonitor. Hubble UI is
protected through Authentik forward-auth.

Security alerts are in `infrastructure/monitoring/security-rules.yaml` and cover
cert expiry, ExternalSecret sync errors, Falco events, Kyverno violations, and
Velero scheduled backup failures.

## Grafana credentials

Grafana admin credentials are stored in 1Password item `grafana`:

| Field | Kubernetes key |
|-------|----------------|
| `username` | `admin-user` |
| `password` | `admin-password` |

ESO creates:

```text
Secret/monitoring/grafana-admin-credentials
```

Verify:

```bash
kubectl get externalsecret grafana-admin-credentials -n monitoring
kubectl get secret grafana-admin-credentials -n monitoring
```

Do not print secret values unless there is a specific reason.

## Health checks

Check pods:

```bash
kubectl get pods -n monitoring
```

Expected key pods:

- `kube-prometheus-stack-grafana-*`
- `kube-prometheus-stack-operator-*`
- `kube-prometheus-stack-kube-state-metrics-*`
- `kube-prometheus-stack-prometheus-node-exporter-*`
- `alertmanager-kube-prometheus-stack-alertmanager-0`
- `prometheus-kube-prometheus-stack-prometheus-0`

Check ArgoCD apps:

```bash
kubectl get applications -n argocd | grep -E 'monitoring|prometheus'
```

Check endpoints:

```bash
for host in grafana prometheus alertmanager; do
  curl -sk -o /dev/null -w "$host: %{http_code}\n" \
    https://$host.platform.nqlabs.network/
done
```

Expected:

- Grafana: `302` to login
- Prometheus: `302` or `200` depending on path
- Alertmanager: `200`

## Prometheus Talos/local-path gotcha

On this Talos + local-path-provisioner setup, Prometheus must run as root.

Observed failure when running non-root:

```text
Error opening query log file file=/prometheus/queries.active err="open /prometheus/queries.active: permission denied"
panic: Unable to create mmap-ed active query log
```

Why:

- kube-prometheus-stack mounts the PVC with `subPath: prometheus-db`.
- The local-path-backed subPath bind mount failed non-root writes even after ownership
  and fsGroup were corrected.
- Running Prometheus as root resolved the issue.

This is encoded in:

```text
infrastructure/monitoring/kube-prometheus-stack/values.yaml
```

Revisit this if the storage backend changes to Rook/Ceph or another CSI driver.

## Useful Prometheus checks

Port-forward if Gateway is not working:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Query targets:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
open http://localhost:9090/targets
```

Check Prometheus logs:

```bash
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus --tail=100
```

## Alertmanager Discord notifications

Alertmanager sends NQLabs alerts to Discord through an `AlertmanagerConfig`.

Secret flow:

```text
1Password item alertmanager-discord / webhook_url
  → ExternalSecret/monitoring/alertmanager-discord-webhook
  → Secret/monitoring/alertmanager-discord-webhook
  → AlertmanagerConfig/monitoring/discord
  → Alertmanager receiver monitoring/discord/discord
```

Verify the ExternalSecret:

```bash
kubectl get externalsecret alertmanager-discord-webhook -n monitoring
kubectl get secret alertmanager-discord-webhook -n monitoring
```

Do not print the webhook value.

Verify Alertmanager loaded the receiver:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
curl -s http://127.0.0.1:9093/api/v2/status | jq '.config.original'
```

You should see a receiver named:

```text
monitoring/discord/discord
```

The webhook URL should appear redacted as `<secret>`.

Send a synthetic test alert:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

curl -XPOST http://127.0.0.1:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  --data-binary '[
    {
      "labels": {
        "alertname": "NQLabsDiscordTest",
        "severity": "info",
        "namespace": "monitoring",
        "instance": "manual-test",
        "cluster": "lab"
      },
      "annotations": {
        "summary": "NQLabs Discord alert test",
        "description": "Synthetic Alertmanager test alert to verify Discord delivery."
      }
    }
  ]'
```

Discord delivery was validated with `NQLabsDiscordTest`.

## Blackbox endpoint probes

Blackbox Exporter probes the user-facing HTTPS path:

```text
DNS → platform Gateway → TLS → HTTPRoute → Service → Pod
```

Configured targets:

```text
https://argocd.platform.nqlabs.network
https://grafana.platform.nqlabs.network
https://prometheus.platform.nqlabs.network
https://alertmanager.platform.nqlabs.network
https://rollouts.platform.nqlabs.network
https://demo.staging.nqlabs.network
https://demo.production.nqlabs.network
```

Resources:

```text
Application/argocd/blackbox-exporter
Probe/monitoring/nqlabs-endpoints
PrometheusRule/monitoring/nqlabs-endpoint-alerts
```

Verify probe metrics:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

curl -sG http://127.0.0.1:9090/api/v1/query \
  --data-urlencode 'query=probe_success{job="nqlabs-endpoints"}' | jq
```

Expected: one `probe_success=1` series for each target.

Check response time:

```promql
probe_duration_seconds{job="nqlabs-endpoints"}
```

Check certificate expiry in days:

```promql
(probe_ssl_earliest_cert_expiry{job="nqlabs-endpoints"} - time()) / 86400
```

Current alert rules:

| Alert | Severity | Meaning |
|-------|----------|---------|
| `NQLabsEndpointDown` | critical | Endpoint probe failed for 2 minutes |
| `NQLabsEndpointSlow` | warning | Endpoint took >2s for 5 minutes |
| `NQLabsEndpointTLSExpiringSoon` | warning | TLS certificate expires in <14 days |

Implementation note: `.network` endpoints now use publicly trusted Let's Encrypt
certificates issued through Cloudflare DNS-01, so in-cluster Blackbox probes should
verify TLS normally. Future external/client-side probes should validate the same
public trust path from outside the cluster.

## Future uptime dashboard

The mature target is:

```text
Internal Blackbox Exporter
+ external/client-side probe location
+ Uptime Kuma as a human-friendly status dashboard
```

Do not rely only on an uptime tool running inside the same cluster. If the cluster
is fully down, the monitor would be down too. An external vantage point is needed
for true user-path monitoring.

## Loki/Promtail

Logging is installed through two ArgoCD apps:

- `loki` — `grafana/loki` chart, single-binary mode, filesystem storage, `20Gi` local-path PVC
- `promtail` — `grafana/promtail` chart, DaemonSet log shipper
- `monitoring-config` — Grafana datasource ConfigMap for Loki

Loki is intentionally not exposed through Gateway API. Grafana reaches it internally:

```text
http://loki-gateway.monitoring.svc.cluster.local
```

Validate Loki readiness and labels with port-forward:

```bash
kubectl port-forward -n monitoring svc/loki-gateway 3100:80
curl http://127.0.0.1:3100/loki/api/v1/labels
```

Validate log ingestion:

```bash
curl -G 'http://127.0.0.1:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="argocd"}' \
  --data-urlencode 'limit=5'
```

In Grafana:

1. Open `https://grafana.platform.nqlabs.network`
2. Go to **Explore**
3. Select datasource **Loki**
4. Query:

```logql
{namespace="argocd"}
```

Promtail is deprecated upstream in favor of Grafana Alloy, but remains simple and
appropriate for Phase 0. Revisit Alloy during the NUC/operations phases.
