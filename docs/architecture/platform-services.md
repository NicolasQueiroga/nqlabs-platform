# NQLabs Platform — Service Reference

> **Status:** Live. Every service listed here is deployed and managed by ArgoCD GitOps.
> This document is the single source of truth for *what runs, where it runs, and how it
> fits together*. For operational procedures, see the linked runbooks.

## Table of Contents

1. [Cluster Topology](#1-cluster-topology)
2. [Networking](#2-networking)
3. [DNS](#3-dns)
4. [Security](#4-security)
5. [Identity & Access](#5-identity--access)
6. [Delivery & GitOps](#6-delivery--gitops)
7. [Monitoring & Observability](#7-monitoring--observability)
8. [Storage](#8-storage)
9. [Backup & Disaster Recovery](#9-backup--disaster-recovery)
10. [Service Factory](#10-service-factory)
11. [Request Flow](#11-request-flow-end-to-end)
12. [Secret Management](#12-secret-management)
13. [Quick Reference](#13-quick-reference)

---

## 1. Cluster Topology

NQLabs runs a three-cluster model on Talos Linux VMs atop a Proxmox host.

```
nqlabs-management   VM  192.168.15.31   ArgoCD, platform tools, identity, monitoring
nqlabs-staging      VM  192.168.15.32   Staging workloads + preview environments
nqlabs-production   VM  192.168.15.33   Production workloads
```

The management cluster is the **control plane for the platform itself**. It runs
ArgoCD, which deploys platform infrastructure to itself and deploys application
workloads to the staging and production clusters by **cluster name** (not IP),
making the system robust to address changes.

All three clusters run:
- **Talos Linux** (immutable, API-driven OS)
- **Cilium** (CNI, kube-proxy replacement, Gateway API, Hubble)
- **Kyverno** (policy engine, audit mode)
- **Falco** (runtime security, eBPF)
- **cert-manager** (TLS certificates)
- **External Secrets Operator** (1Password integration)
- **local-path-provisioner** (storage)

The management cluster additionally runs all platform services (identity,
monitoring, DNS, backup, delivery, service factory).

Design decision: [cluster-topology.md](../decisions/cluster-topology.md)

---

## 2. Networking

### Cilium (CNI + Gateway API + Hubble)

| Property | Value |
|----------|-------|
| Namespace | `kube-system` |
| Chart | `cilium/cilium` v1.19.4 |
| Mode | kube-proxy replacement (eBPF), L2 announcements |
| Gateway API | Enabled — Cilium serves as the GatewayClass controller |
| Hubble | Enabled (relay + UI) for network observability |

Cilium does three jobs:

1. **CNI** — replaces kube-proxy entirely with eBPF. All pod networking,
   service routing, and network policy run in the eBPF datapath.
2. **Gateway API** — the `cilium` GatewayClass controller provisions the
   `platform-gateway` LoadBalancer, which is the HTTPS entry point for all
   `*.nqlabs.network` services. L2 announcements advertise the LB IP on the
   LAN.
3. **Hubble** — network flow observability. Hubble Relay + UI provide a
   service map and live flow visualization.

LB IPAM pool: `192.168.15.192/28` (announced via L2 on the node's physical NIC).

Config: `infrastructure/networking/cilium/values.yaml`

### Gateway API — Platform Gateway

| Property | Value |
|----------|-------|
| Namespace | `platform` |
| Gateway name | `platform-gateway` |
| GatewayClass | `cilium` |
| LB IP | `192.168.15.195` (from Cilium LB IPAM) |
| TLS | Let's Encrypt wildcard cert (`*.platform.nqlabs.network`,
      `*.staging.nqlabs.network`, `*.production.nqlabs.network`) |
| TLS mode | Terminate at gateway |

The gateway listens on:
- **:443** (HTTPS) — TLS terminated, routes to backend services over HTTP
- **:80** (HTTP) — redirects to HTTPS

Namespaces must carry the `gateway-access: "true"` label to attach HTTPRoutes.
This prevents unauthorized namespaces from hijacking hostnames. Currently
labeled: `argocd`, `monitoring`, `authentik`, `argo-rollouts`, `platform`,
`kube-system`.

HTTPRoutes attach to the gateway and route by hostname:

| Hostname | Backend Service | Namespace | Auth |
|----------|----------------|-----------|------|
| `argocd.platform.nqlabs.network` | `argocd-server:80` | argocd | OIDC |
| `grafana.platform.nqlabs.network` | `kube-prometheus-stack-grafana:80` | monitoring | OIDC |
| `auth.platform.nqlabs.network` | `authentik-server:80` | authentik | — |
| `prometheus.platform.nqlabs.network` | `authentik-server:80` (forward-auth) → `kube-prometheus-stack-prometheus:9090` | monitoring | Forward-auth |
| `alertmanager.platform.nqlabs.network` | `authentik-server:80` (forward-auth) → `kube-prometheus-stack-alertmanager:9093` | monitoring | Forward-auth |
| `rollouts.platform.nqlabs.network` | `authentik-server:80` (forward-auth) → `argo-rollouts-dashboard:3100` | argo-rollouts | Forward-auth |
| `uptime.platform.nqlabs.network` | `authentik-server:80` (forward-auth) → `uptime-kuma:3001` | monitoring | Forward-auth |

Config: `infrastructure/networking/gateway/platform-gateway.yaml`

### Tailscale (Private Access Layer)

| Property | Value |
|----------|-------|
| Namespace | `tailscale` |
| Tailnet | `hen-exponential.ts.net` |
| Operator | `tailscale/tailscale-operator` |
| OAuth | ESO-managed (1Password → `tailscale-oauth` ExternalSecret) |

Tailscale provides private network access to all cluster services. No
platform service is exposed to the public internet — everything is reached
through the Tailscale tailnet.

**Components:**

1. **Tailscale Operator** — manages Tailscale resources in the cluster
   (Connectors, Services with `loadBalancerClass: tailscale`).
2. **Lab Subnet Router** (`Connector`) — advertises the desktop LAN subnet
   `192.168.15.0/24` to the tailnet, so all Tailscale devices can reach
   cluster LoadBalancer IPs directly.
3. **CoreDNS Tailscale Service** — a `LoadBalancer` with
   `loadBalancerClass: tailscale` that gives CoreDNS a Tailscale IP
   (`100.120.180.12`). This IP is configured as the Tailscale split DNS
   nameserver for `nqlabs.network`.

**Split DNS flow:**
```
Tailnet device queries *.nqlabs.network
  → Tailscale split DNS → 100.120.180.12 (CoreDNS)
  → CoreDNS resolves from etcd (records written by external-dns)
  → Returns the Cilium Gateway LB IP (192.168.15.195)
  → Tailnet device connects to gateway over Tailscale subnet route
```

Config: `infrastructure/networking/tailscale/`

### Cloudflare Tunnel (Public Edge)

| Property | Value |
|----------|-------|
| Namespace | `cloudflared` |
| Deployment | 2 replicas, `cloudflare/cloudflared` |
| Tunnel token | ESO-managed (1Password) |

Cloudflare Tunnel gives `*.nqlabs.io` (public domain) services a real public
ingress without exposing a public IP. `cloudflared` dials out to Cloudflare;
Cloudflare terminates public TLS and forwards matched hostnames over the
tunnel. Ingress rules (hostname → origin) are managed in the Cloudflare
dashboard.

Currently deployed to the production cluster only. Not yet wired into the
app-of-apps for the management cluster — activated per the
[public-edge runbook](../runbooks/public-edge-cloudflare.md).

Config: `infrastructure/networking/cloudflared/cloudflared.yaml`

---

## 3. DNS

### Standalone CoreDNS (Authoritative for `nqlabs.network`)

| Property | Value |
|----------|-------|
| Namespace | `dns` |
| Chart | `coredns/coredns` |
| Replicas | 2 |
| Service type | LoadBalancer (Cilium LB IPAM) |
| LB IP | `192.168.15.192` |
| Tailscale IP | `100.120.180.12` (split DNS target) |
| Backend | etcd (SkyDNS protocol) |

This is a **separate** CoreDNS instance from the Kubernetes built-in
`kube-dns` in `kube-system`. It is the authoritative nameserver for the
`nqlabs.network` zone. DNS records are stored in etcd using the SkyDNS
path format and served by CoreDNS.

Exposed via Tailscale so that all tailnet devices can resolve
`*.nqlabs.network` names. The Tailscale admin console is configured with
`nqlabs.network → 100.120.180.12` as a split DNS nameserver.

Config: `infrastructure/dns/coredns/values.yaml`

### etcd (DNS Record Backend)

| Property | Value |
|----------|-------|
| Namespace | `dns` |
| Kind | StatefulSet (single replica) |
| Image | `quay.io/coreos/etcd` |
| Storage | local-path PVC |
| Purpose | Stores DNS A/CNAME records in SkyDNS format |

This etcd instance is **not** the Kubernetes control-plane etcd. It is a
dedicated key-value store for DNS records, written by external-dns and read
by the standalone CoreDNS.

Config: `infrastructure/dns/etcd/manifests/statefulset.yaml`

### external-dns (Record Sync)

| Property | Value |
|----------|-------|
| Namespace | `dns` |
| Chart | `external-dns/external-dns` |
| Provider | CoreDNS (etcd) |
| Sources | Service, Ingress, HTTPRoute |
| Policy | upsert-only (never delete) |
| Domain filter | `nqlabs.network` |

external-dns watches Kubernetes resources for hostname annotations and
writes A/CNAME records into the etcd backend. When a Service or HTTPRoute
carries `external-dns.alpha.kubernetes.io/hostname: foo.platform.nqlabs.network`,
external-dns creates the record in etcd, and CoreDNS serves it.

Config: `infrastructure/dns/external-dns/values.yaml`

### Kubernetes CoreDNS (Cluster DNS)

| Property | Value |
|----------|-------|
| Namespace | `kube-system` |
| Service | `kube-dns` (ClusterIP `10.96.0.10`) |
| Replicas | 2 |

The standard in-cluster DNS for Kubernetes service discovery
(`*.svc.cluster.local`). Managed by the Talos machine config, not ArgoCD.

Design decision: [dns-architecture.md](../decisions/dns-architecture.md)

---

## 4. Security

### cert-manager (TLS Certificates)

| Property | Value |
|----------|-------|
| Namespace | `cert-manager` |
| Chart | `jetstack/cert-manager` |
| Replicas | 2 controller + cainjector + webhook |
| Observability | ServiceMonitor + certificate expiry alerts |
| Network | namespace NetworkPolicy |

Manages TLS certificates for all platform services. Two cluster issuers:

1. **`letsencrypt-prod`** — Let's Encrypt via Cloudflare DNS-01. Issues
   publicly trusted wildcard certificates for `*.nqlabs.network` subdomains.
   The DNS-01 challenge proves domain ownership through temporary TXT
   records in Cloudflare — services remain private (Tailscale-only) but
   have publicly trusted certs (no browser warnings).

2. **`nqlabs-internal-ca`** — Self-signed CA for bootstrap/internal use.
   A 10-year ECDSA root certificate that can issue certs if Let's Encrypt
   is unavailable.

The platform gateway's wildcard certificate covers:
- `*.platform.nqlabs.network`
- `*.staging.nqlabs.network`
- `*.production.nqlabs.network`

Config: `infrastructure/security/cert-manager/`

### External Secrets Operator (Secret Sync)

| Property | Value |
|----------|-------|
| Namespace | `external-secrets` |
| Chart | `external-secrets/external-secrets` v2.6.0 |
| Backend | 1Password SDK (NQLabs vault) |
| Auth | Service account token (one-time bootstrap) |
| Replicas | 2 controller + webhook + cert-controller (leader election on) |
| Observability | ServiceMonitor + sync-error alerts |

ESO synchronizes secrets from 1Password into Kubernetes Secrets. The
platform uses a single `ClusterSecretStore` named `nqlabs-1password` that
reads from the NQLabs vault using a 1Password service account token.

All platform secrets are defined as `ExternalSecret` resources that
reference the `nqlabs-1password` store. When an ExternalSecret is created,
ESO fetches the value from 1Password and materializes a Kubernetes Secret.

**Secrets managed by ESO:**
- `authentik-secrets` — secret_key, bootstrap_password, bootstrap_token,
  redis_password, postgres_password
- `authentik-postgres` — Postgres password for CNPG
- `argocd-oidc-secret` — OIDC client secret for ArgoCD
- `grafana-oidc` — OIDC client secret for Grafana
- `grafana-admin-credentials` — Grafana local admin (break-glass only)
- `velero-credentials` — AWS S3 + Azure Blob backup credentials
- `minio-auth` — MinIO root credentials
- `tailscale-oauth` — Tailscale OAuth client ID + secret
- `cloudflared-tunnel` — Cloudflare tunnel token

Config: `infrastructure/security/external-secrets/`

### Kyverno (Policy Engine)

| Property | Value |
|----------|-------|
| Namespace | `kyverno` |
| Chart | `kyverno/kyverno` |
| Mode | Enforce for baseline/platform guardrails and image signature verification |
| Controllers | Admission (1), Background (1), Reports (1), Cleanup (1) |

Kyverno enforces platform security policies. Baseline ClusterPolicies
are currently in **Enforce** mode with webhook `failurePolicy: Ignore`
(so Kyverno being down never blocks admission):

1. **`disallow-latest-tag`** — rejects container images tagged `:latest`
2. **`require-resource-requests`** — requires CPU/memory requests on all pods
3. **`restrict-image-registries`** — allows only approved registries
   (docker.io, ghcr.io, quay.io, registry.k8s.io, ecr-public.aws.com)
4. **`require-run-as-nonroot`** — requires pods to run as non-root user
5. **`disallow-privileged-containers`**, **`require-seccomp`**,
   **`disallow-host-namespace`**, **`restrict-capabilities`**,
   **`disallow-host-path`** — pod security controls
6. **NQLabs service-namespace guardrails** — required labels, memory limits,
   generated CiliumNetworkPolicy/ResourceQuota/LimitRange, and managed-label mutation

Additionally, `verify-image-signatures` enforces Cosign keyless signatures on
`ghcr.io/nicolasqueiroga/*` images produced by GitHub Actions.

Autogen is enabled, so Pod policies validate controller templates as well as
raw Pods. Kyverno metrics are scraped with ServiceMonitors and surfaced through
PolicyReports/Prometheus alerts.

System namespaces (kube-system, falco, tailscale, local-path-storage,
velero, monitoring, dns) are excluded from pod policies.

Kyverno is replicated to staging and production clusters.

Config: `infrastructure/security/kyverno/`

### Falco (Runtime Security)

| Property | Value |
|----------|-------|
| Namespace | `falco` |
| Chart | `falcosecurity/falco` |
| Driver | modern_ebpf (CO-RE, no kernel module) |
| Mode | Detection/alert only (never blocks) |
| Priority | `system-node-critical` |
| Tolerations | All nodes (including control plane) |
| Observability | metrics ServiceMonitor + custom NQLabs rules |

Falco instruments kernel syscalls via eBPF and alerts on suspicious
runtime behavior (unexpected process execution, file access, network
connections). JSON events are output to stdout and collected by promtail
into Loki for correlation with other observability data. Management also runs
Falcosidekick to forward warning+ events to Alertmanager.

Runs as a DaemonSet on all nodes. Requires privileged mode (intentional —
needed for eBPF kernel instrumentation).

Config: `infrastructure/security/falco/values.yaml`

---

## 5. Identity & Access

### Authentik (Identity Provider)

| Property | Value |
|----------|-------|
| Namespace | `authentik` |
| Chart | `authentik/authentik` |
| URL | `auth.platform.nqlabs.network` |
| Admin user | `akadmin` (password in 1Password: `authentik/bootstrap_password`) |
| API token | 1Password: `authentik/bootstrap_token` |
| Database | CloudNativePG (`authentik-pg`) |
| Cache | Valkey (`authentik-valkey`) |

Authentik is the single identity provider for the platform. Every platform
UI authenticates against it.

**Authentication methods by service:**

| Service | Method | How it works |
|---------|--------|-------------|
| ArgoCD | OIDC (native) | ArgoCD redirects to Authentik `/authorize`, receives ID token with `groups` claim. RBAC maps `platform-admins` → `role:admin`, `platform-viewers` → `role:readonly`. Local admin disabled. |
| Grafana | OIDC (native) | Grafana redirects to Authentik `/authorize`, receives ID token. `role_attribute_path` maps `platform-admins` → Admin, else Viewer. Login form disabled; auto-redirect to Authentik. |
| Prometheus | Forward-auth (embedded proxy outpost) | Gateway routes to Authentik outpost first; outpost validates session, redirects unauthenticated users to Authentik login, passes through authenticated users to the backend. |
| Alertmanager | Forward-auth | Same as Prometheus. |
| Argo Rollouts Dashboard | Forward-auth | Same as Prometheus. |
| Uptime Kuma | Forward-auth | Same as Prometheus. |

**Groups (defined in blueprints):**

| Group | Access level |
|-------|-------------|
| `platform-admins` | Full admin across all UIs (Authentik superuser) |
| `platform-viewers` | Read-only across all UIs |

**Blueprints:**
- `10-groups.yaml` — defines `platform-admins` and `platform-viewers` groups
  + a `groups` scope mapping that adds the `groups` claim to OIDC tokens
- `20-oidc.yaml` — defines OIDC providers + applications for ArgoCD and Grafana
- `30-proxy.yaml` — defines proxy providers for forward-auth services +
  the embedded outpost

Blueprints reconcile automatically (mounted ConfigMap, discovered by the
worker). Force: `kubectl exec -n authentik deploy/authentik-worker -- ak apply_blueprint /blueprints/mounted/cm-authentik-blueprints/<file>.yaml`

Config: `infrastructure/identity/authentik/`
Runbook: [sso-authentik.md](../runbooks/sso-authentik.md)

### CloudNativePG (PostgreSQL Operator)

| Property | Value |
|----------|-------|
| Namespace | `cnpg-system` (operator), `authentik` (cluster) |
| Chart | `cnpg/cloudnative-pg` |
| Cluster | `authentik-pg` (1 replica, read-write + read-only services) |
| Storage | local-path PVC |
| Image | `ghcr.io/cloudnative-pg/*` |

Provides operator-managed PostgreSQL for Authentik. The operator manages
the `authentik-pg-rw` (read-write) and `authentik-pg-ro` (read-only)
services. Available for future stateful services needing Postgres.

Config: `infrastructure/identity/cloudnative-pg/values.yaml`,
`infrastructure/identity/authentik/manifests/postgres-cluster.yaml`

### Valkey (Redis-compatible Cache)

| Property | Value |
|----------|-------|
| Namespace | `authentik` |
| Kind | StatefulSet (single replica) |
| Storage | local-path PVC |

Caching layer for Authentik sessions and rate limiting. Deployed as a
manifest (not a chart) alongside the Authentik installation.

Config: `infrastructure/identity/authentik/manifests/valkey.yaml`

---

## 6. Delivery & GitOps

### ArgoCD (GitOps Controller)

| Property | Value |
|----------|-------|
| Namespace | `argocd` |
| Chart | `argo/argo-cd` |
| URL | `argocd.platform.nqlabs.network` |
| Auth | OIDC via Authentik (local admin disabled) |
| RBAC | `platform-admins` → admin, `platform-viewers` → readonly |
| Repo | `github.com/NicolasQueiroga/nqlabs-platform` |
| Components | Application controller, ApplicationSet controller, repo server, Redis, server (UI) |

ArgoCD is the GitOps controller for the entire platform. It watches the
Git repository and reconciles cluster state to match declarative manifests.

**App-of-apps pattern:**
```
root Application (watches clusters/nqlabs-management/argocd/apps/)
  ├── Platform infrastructure apps (argocd, cert-manager, cilium, etc.)
  ├── Service factory (services ApplicationSet)
  ├── Staging foundation apps (replicated to staging cluster)
  └── Production foundation apps (replicated to production cluster)
```

**AppProjects:**
- `platform` — platform infrastructure apps
- `services-staging` — staging application workloads
- `services-production` — production application workloads
- `services-preview` — ephemeral preview environments

**Orphaned-resource policy:** orphan warnings are disabled for the `platform`
project and kept enabled for `services-staging`/`services-production`. Platform
namespaces are intentionally co-managed by GitOps and operators: cert-manager,
External Secrets Operator, Prometheus Operator, Tailscale Operator, CNPG, Helm,
ArgoCD cluster registration, Velero, and bootstrap credentials all create
runtime resources that are expected to be absent from Git. A curated ignore list
for those resources becomes brittle and incomplete, especially where operators
create random-suffixed resources. Service namespaces are different: each service
owns its namespace, so orphan warnings there still indicate real workload drift.

ArgoCD runs in insecure mode (HTTP) — TLS is terminated at the platform
gateway. The OIDC config uses Authentik as the issuer with the `groups`
scope for RBAC.

Config: `platform/argocd/values.yaml`
Runbook: [argocd-bootstrap.md](../runbooks/argocd-bootstrap.md)

### Argo Rollouts (Progressive Delivery)

| Property | Value |
|----------|-------|
| Namespace | `argo-rollouts` |
| Chart | `argo/argo-rollouts` |
| Controller | 1 replica |
| Dashboard | `rollouts.platform.nqlabs.network` (read-only, forward-auth) |
| Traffic router | Gateway API plugin (exact-weight canary via weighted HTTPRoute) |

Argo Rollouts provides progressive delivery (canary deployments). It
replaces standard Deployments with Rollout objects that support:

- **Replica-ratio canary** — basic canary by adjusting replica counts
- **Exact-weight canary** — uses the Gateway API traffic router plugin to
  shift traffic by exact percentage via weighted HTTPRoute backendRefs
- **Analysis** — background HTTP-2xx analysis during rollouts for
  automated promote/rollback decisions

The dashboard is read-only (mutations should go through git/ArgoCD or
kubectl plugin).

Config: `infrastructure/delivery/argo-rollouts/values.yaml`

### Service Factory (ApplicationSet)

| Property | Value |
|----------|-------|
| Namespace | `argocd` |
| Kind | ApplicationSet |
| Generator | Git (files: `apps/*/environments/*.yaml`) |
| Chart | `charts/nqlabs-service` (v0.8.0) |

The service factory is the heart of the platform's application delivery.
A single ApplicationSet generates one ArgoCD Application per
`apps/<app>/environments/<env>.yaml` descriptor file. Each descriptor
declares where the service runs (cluster name + namespace), what image
to deploy, and how to route traffic.

**Descriptor structure:**
```
apps/demo/
  app.yaml                    # Identity + default shape (env-independent)
  environments/
    staging.yaml              # Staging runtime state (image tag, route host)
    production.yaml           # Production runtime state (canary steps)
  previews/                   # Ephemeral per-PR preview descriptors
```

The `nqlabs-service` chart renders from a descriptor:
- Deployment or Rollout (single or multi-workload)
- Service + ServiceAccount
- HTTPRoute (internal, public, or preview)
- HPA, PDB, ServiceMonitor
- ExternalSecret (for declared secret dependencies)
- CiliumNetworkPolicy (default-deny ingress baseline)
- ConfigMap, LimitRange, ResourceQuota

**End-to-end flow:**
```
PR to app repo           → build/test (+ optional /preview deploy)
merge to app main        → build image, update staging descriptor → ArgoCD deploys staging
release PR → vX.Y.Z tag  → promote artifact → production PR → merge → ArgoCD deploys production (canary)
```

Architecture: [service-factory.md](service-factory.md)
Runbook: [onboarding-a-new-application.md](../runbooks/onboarding-a-new-application.md)

---

## 7. Monitoring & Observability

### Prometheus (Metrics Collection)

| Property | Value |
|----------|-------|
| Namespace | `monitoring` |
| Chart | `prometheus-community/kube-prometheus-stack` |
| URL | `prometheus.platform.nqlabs.network` (forward-auth) |
| Storage | local-path PVC (20Gi) |
| Retention | 15d (or as configured) |
| Mode | Single instance (StatefulSet) |

Prometheus scrapes metrics from all platform components via ServiceMonitor
and PodMonitor resources. It also scrapes Kubernetes system components
(kubelet, CoreDNS, node-exporter) and application services that expose
Prometheus-compatible metrics.

The kube-prometheus-stack chart bundles:
- Prometheus (metrics collection)
- Alertmanager (alert routing)
- Grafana (visualization)
- kube-state-metrics (Kubernetes object state metrics)
- node-exporter (host-level metrics)
- Prometheus operator (manages Prometheus/Alertmanager instances)

Config: `infrastructure/monitoring/kube-prometheus-stack/values.yaml`

### Grafana (Visualization)

| Property | Value |
|----------|-------|
| Namespace | `monitoring` |
| URL | `grafana.platform.nqlabs.network` (OIDC) |
| Auth | OIDC via Authentik (login form disabled, auto-redirect) |
| Storage | local-path PVC (5Gi) for dashboard persistence |
| Dashboards | Sidecar-provisioned from ConfigMaps (searchNamespace: ALL) |

Grafana is the primary visualization layer. It uses Prometheus as the
default data source and includes all kube-prometheus-stack dashboards
plus any dashboards discovered from ConfigMaps across all namespaces.

Role mapping: `platform-admins` group → Grafana Admin, all others → Viewer.

Config: `infrastructure/monitoring/kube-prometheus-stack/values.yaml`

### Alertmanager (Alert Routing)

| Property | Value |
|----------|-------|
| Namespace | `monitoring` |
| URL | `alertmanager.platform.nqlabs.network` (forward-auth) |
| Storage | local-path PVC (2Gi) |
| Notification | Discord webhook |

Alertmanager receives alerts from Prometheus and routes them to
notification channels. Currently configured with a Discord webhook
integration for alert delivery.

Config: `infrastructure/monitoring/alertmanager-discord.yaml`

### Loki (Log Aggregation)

| Property | Value |
|----------|-------|
| Namespace | `monitoring` |
| Chart | `grafana/loki` v7.0.0 |
| Mode | SingleBinary + filesystem PVC |
| Storage | local-path (filesystem) |
| Retention | 7 days (168h) |
| Auth | Disabled (internal only) |

Loki is the log aggregation system. It stores logs in a filesystem-backed
single-binary mode (suitable for single-node; will move to object storage
or distributed mode for production/NUC). Logs are queried through Grafana's
Loki data source.

Config: `infrastructure/monitoring/loki/values.yaml`

### Promtail (Log Shipping)

| Property | Value |
|----------|-------|
| Namespace | `monitoring` |
| Chart | `grafana/promtail` |
| Kind | DaemonSet (runs on all nodes) |
| Target | `loki-gateway.monitoring.svc.cluster.local` |

Promtail runs as a DaemonSet on every node, collecting container logs from
`/var/log` and `/var/lib/docker/containers`, adding Kubernetes metadata
labels, and shipping them to Loki via the Loki gateway.

Also collects Falco runtime security events (JSON output from Falco's
stdout) for correlation in Loki.

Config: `infrastructure/monitoring/promtail/values.yaml`

### Blackbox Exporter (Synthetic Monitoring)

| Property | Value |
|----------|-------|
| Namespace | `monitoring` |
| Chart | `prometheus-community/prometheus-blackbox-exporter` |
| Modules | `http_2xx_internal`, `http_302_auth` |

Blackbox exporter performs HTTP probes against platform endpoints. Three
Probes are defined:

1. **`nqlabs-internal-health`** — probes service endpoints directly
   (bypassing gateway/auth), expects 2xx from health endpoints
2. **`nqlabs-edge-auth`** — probes public URLs for forward-auth services,
   expects 302 redirect to Authentik (does not follow redirects)
3. **`nqlabs-edge-oidc`** — probes public URLs for OIDC services,
   expects 2xx login page

This split ensures that probes test the right thing: internal health probes
verify the backend is up, while edge probes verify the auth redirect is
working — without conflating the two.

Config: `infrastructure/monitoring/blackbox/values.yaml`,
`infrastructure/monitoring/blackbox-probes.yaml`

### Uptime Kuma (Uptime Monitoring)

| Property | Value |
|----------|-------|
| Namespace | `monitoring` |
| URL | `uptime.platform.nqlabs.network` (forward-auth) |
| Storage | local-path PVC |
| Kind | Deployment (manifest, not chart) |

Uptime Kuma provides a user-friendly uptime monitoring UI. It complements
Prometheus/blackbox probes with a visual dashboard for uptime status and
notification configuration.

Config: `infrastructure/monitoring/uptime-kuma/`

### Hubble (Network Observability)

| Property | Value |
|----------|-------|
| Namespace | `kube-system` |
| Components | Hubble Relay + Hubble UI |
| Access | `hubble.platform.nqlabs.network` via Authentik forward-auth; `hubble observe` CLI |
| Metrics | `hubble-metrics` ServiceMonitor + Grafana dashboard |

Hubble is part of Cilium and provides deep network flow observability. It
shows a service map of all network connections in the cluster, with
filtering by namespace, pod, and policy. Accessed via `hubble observe` CLI
or the Authentik-protected Hubble UI.

Config: `infrastructure/networking/cilium/values.yaml`

---

## 8. Storage

### local-path-provisioner

| Property | Value |
|----------|-------|
| Namespace | `local-path-storage` |
| Chart | `rancher/local-path-provisioner` |
| StorageClass | `local-path` (default) |
| Volume binding | WaitForFirstConsumer |
| Host path | `/opt/local-path-provisioner` |

Provides ephemeral, single-node storage via hostPath. This is the default
StorageClass — PVCs without an explicit storage class use local-path. No
replication; data is lost if the node disk fails. Acceptable for the lab
environment; will be replaced by Rook/Ceph when distributed storage is
available.

Config: `infrastructure/storage/local-path/values.yaml`

### MinIO (S3-Compatible Object Storage)

| Property | Value |
|----------|-------|
| Namespace | `minio` |
| Kind | Deployment (manifest) |
| Storage | local-path PVC (20Gi) |
| Credentials | ESO-managed (1Password: `velero-minio`) |
| Ports | 9000 (S3 API), 9001 (console) |

MinIO provides S3-compatible object storage as the local backup target for
Velero. It is a backup target, not durable storage — offsite backups (AWS
S3, Azure Blob) provide real DR.

Config: `infrastructure/storage/minio/minio.yaml`

---

## 9. Backup & Disaster Recovery

### Velero (Backup/DR)

| Property | Value |
|----------|-------|
| Namespace | `velero` |
| Kind | Deployment (1 replica) |
| Mode | scheduled + on-demand; node-agent file backup enabled |
| Backup targets | management: MinIO/AWS/Azure; staging/production: AWS/Azure |

Velero provides Kubernetes backup and disaster recovery. It runs on all three
clusters. Scheduled backups provide baseline coverage; operators can still
trigger pre-change backups manually.

**Three backup storage locations:**

| Location | Provider | Bucket | Purpose |
|----------|----------|--------|---------|
| `minio` (default) | AWS (S3 API) | `velero` on MinIO | Local, fast, free |
| `aws` | AWS S3 | `nqlabs-velero-backup` (us-east-1) | Offsite DR |
| `azure` | Azure Blob | `velero` (Cool tier) | Cheapest offsite |

Usage:
```bash
velero backup create pre-change-snapshot --storage-location minio
velero backup create dr-snapshot --storage-location aws
```

Config: `infrastructure/backup/velero/values.yaml`
Runbook: [backup-velero.md](../runbooks/backup-velero.md)

---

## 10. Service Factory

The service factory is the platform's application delivery system. It
turns "I want a new application" into running staging, production, and
preview environments with repeatable automation.

### How it works

1. **Application identity** — `apps/<app>/app.yaml` defines the stable,
   environment-independent identity (name, description, owner, repository,
   exposure intent, default workload shape, security policy).

2. **Per-environment state** — `apps/<app>/environments/<env>.yaml`
   declares runtime state (image tag, namespace, cluster destination,
   route host, rollout strategy). Merged under `app.yaml` (env wins).

3. **ApplicationSet** — the `services` ApplicationSet in
   `clusters/nqlabs-management/services/manifests/applicationset.yaml`
   watches for `apps/*/environments/*.yaml` files and generates one
   ArgoCD Application per descriptor.

4. **Service chart** — `charts/nqlabs-service` (v0.8.0) renders the
   descriptor into Kubernetes resources: Deployment/Rollout, Service,
   HTTPRoute, ServiceAccount, HPA, PDB, ServiceMonitor, ExternalSecret,
   CiliumNetworkPolicy, ConfigMap, LimitRange, ResourceQuota.

5. **Cluster-aware delivery** — Applications are deployed by cluster
   **name** (`nqlabs-staging`, `nqlabs-production`), not IP. The clusters
   are registered in ArgoCD with those exact names.

### Adding a new application

Copy the app-repo caller workflows and add `apps/<app>/environments/*.yaml`
descriptors — no new AppProject, ApplicationSet, gateway, cert, DNS, or
edge rule required.

Runbook: [onboarding-a-new-application.md](../runbooks/onboarding-a-new-application.md)
Architecture: [service-factory.md](service-factory.md)

### Preview environments

Per-PR ephemeral previews with a 1h TTL, driven by PR comments
(`/preview deploy|renew|destroy|status`) and reusable platform workflows.

Runbook: [preview-environments.md](../runbooks/preview-environments.md)

---

## 11. Request Flow (End-to-End)

### How a user reaches ArgoCD

```
User on tailnet device
  → DNS: argocd.platform.nqlabs.network
  → Tailscale split DNS → CoreDNS (100.120.180.12)
  → CoreDNS resolves from etcd → 192.168.15.195 (Cilium Gateway LB)
  → User connects to gateway:443 over Tailscale subnet route
  → Gateway terminates TLS (Let's Encrypt wildcard cert)
  → HTTPRoute matches argocd.platform.nqlabs.network → argocd-server:80
  → ArgoCD redirects to Authentik OIDC /authorize
  → User authenticates at Authentik
  → Authentik returns ID token with groups claim
  → ArgoCD RBAC: platform-admins → role:admin
  → User sees ArgoCD dashboard
```

### How a user reaches Prometheus (forward-auth)

```
User on tailnet device
  → DNS: prometheus.platform.nqlabs.network → 192.168.15.195
  → Gateway terminates TLS
  → HTTPRoute matches → authentik-server:80 (forward-auth outpost)
  → Outpost checks session cookie
    → No session → 302 redirect to Authentik login
    → Valid session → outpost passes request to kube-prometheus-stack-prometheus:9090
  → Prometheus serves the page
```

### How a Git commit reaches production

```
Developer merges PR to app repo main
  → CI builds image, pushes to ghcr.io
  → CI updates apps/<app>/environments/staging.yaml in platform repo
  → ArgoCD detects change → deploys to nqlabs-staging cluster
  → Developer creates release PR → tags vX.Y.Z
  → CI updates apps/<app>/environments/production.yaml
  → ArgoCD deploys to nqlabs-production via Argo Rollouts canary
  → Rollout: 10% → pause → 25% → pause → 50% → pause → 100%
  → Background analysis monitors HTTP 2xx rate during canary
  → Auto-promote or auto-rollback based on analysis
```

---

## 12. Secret Management

All secrets are stored in 1Password and synchronized to Kubernetes by
External Secrets Operator. No secrets exist in the Git repository.

### Flow

```
1Password (NQLabs vault)
  → ESO ClusterSecretStore (nqlabs-1password)
  → ExternalSecret resources reference 1Password item fields
  → ESO creates Kubernetes Secrets
  → Pods consume secrets via secretKeyRef / envFromSecret
```

### Key secrets

| 1Password item | Fields | Used by |
|----------------|--------|---------|
| `authentik` | secret_key, bootstrap_password, bootstrap_token, redis_password, postgres_password | Authentik server/worker |
| `authentik-postgres` | password | CNPG cluster + Authentik |
| `argocd-oidc` | client_secret | ArgoCD OIDC + Authentik blueprint |
| `grafana-oidc` | client_secret | Grafana OIDC + Authentik blueprint |
| `grafana-admin-credentials` | admin-user, admin-password | Grafana (break-glass only) |
| `velero-credentials` | aws, azure | Velero backup targets |
| `velero-minio` | access-key, secret-key | MinIO + Velero |
| `tailscale-key` | username (client_id), credential (client_secret) | Tailscale operator OAuth |
| `cloudflared-tunnel` | tunnel-token | Cloudflare tunnel |
| `Service Account Auth Token: NQ Labs` | credential (ops_...) | ESO bootstrap (one-time) |

Runbook: [secrets.md](../runbooks/secrets.md)

---

## 13. Quick Reference

### All ArgoCD Applications (53 total)

**Management cluster platform infrastructure:**

| App | Namespace | Purpose |
|-----|-----------|---------|
| `root` | argocd | App-of-apps root |
| `argocd` | argocd | ArgoCD (self-managed) |
| `argo-rollouts` | argo-rollouts | Progressive delivery controller |
| `authentik` | authentik | Identity provider |
| `cloudnative-pg` | cnpg-system | PostgreSQL operator |
| `cert-manager` | cert-manager | TLS certificate management |
| `cert-manager-config` | cert-manager | ClusterIssuers + ExternalSecrets |
| `external-secrets` | external-secrets | Secret sync operator |
| `external-secrets-config` | external-secrets | ClusterSecretStore |
| `gateway` | platform | Cilium Gateway API gateway |
| `kube-prometheus-stack` | monitoring | Prometheus + Grafana + Alertmanager |
| `monitoring-config` | monitoring | Routes, probes, datasources, policies |
| `loki` | monitoring | Log aggregation |
| `promtail` | monitoring | Log shipping DaemonSet |
| `blackbox-exporter` | monitoring | Synthetic monitoring |
| `uptime-kuma` | monitoring | Uptime monitoring UI |
| `management-kyverno` | kyverno | Policy engine |
| `management-kyverno-policies` | kyverno | ClusterPolicies |
| `management-falco` | falco | Runtime security |
| `management-velero` | velero | Backup/DR |
| `management-minio` | minio | S3-compatible backup target |
| `local-path-provisioner` | local-path-storage | Storage provisioner |
| `coredns-dns` | dns | Authoritative DNS for nqlabs.network |
| `etcd-dns` | dns | DNS record backend |
| `external-dns` | dns | DNS record sync |
| `tailscale-operator` | tailscale | Tailscale operator |
| `tailscale-config` | tailscale | Subnet router + CoreDNS exposure |
| `service-factory` | argocd | Services ApplicationSet |
| `demo-staging` | demo | Demo service (staging) |
| `demo-production` | demo | Demo service (production) |

**Staging cluster foundation (replicated):**

| App | Namespace | Purpose |
|-----|-----------|---------|
| `staging-cert-manager` | cert-manager | TLS certs |
| `staging-cert-manager-config` | cert-manager | ClusterIssuers |
| `staging-external-secrets` | external-secrets | Secret sync |
| `staging-external-secrets-config` | external-secrets | ClusterSecretStore |
| `staging-kyverno` | kyverno | Policy engine |
| `staging-kyverno-policies` | kyverno | ClusterPolicies |
| `staging-falco` | falco | Runtime security |
| `staging-gateway` | platform | Gateway API |
| `staging-cilium-config` | kube-system | Cilium LB IPAM |
| `staging-local-path-provisioner` | local-path-storage | Storage |
| `staging-argo-rollouts` | argo-rollouts | Progressive delivery |

**Production cluster foundation (replicated):**

| App | Namespace | Purpose |
|-----|-----------|---------|
| `production-cert-manager` | cert-manager | TLS certs |
| `production-cert-manager-config` | cert-manager | ClusterIssuers |
| `production-external-secrets` | external-secrets | Secret sync |
| `production-external-secrets-config` | external-secrets | ClusterSecretStore |
| `production-kyverno` | kyverno | Policy engine |
| `production-kyverno-policies` | kyverno | ClusterPolicies |
| `production-falco` | falco | Runtime security |
| `production-gateway` | platform | Gateway API |
| `production-cilium-config` | kube-system | Cilium LB IPAM |
| `production-cloudflared` | cloudflared | Cloudflare Tunnel (public edge) |
| `production-local-path-provisioner` | local-path-storage | Storage |
| `production-argo-rollouts` | argo-rollouts | Progressive delivery |

### All Namespaces

| Namespace | Pod Security | Purpose |
|-----------|-------------|---------|
| `argocd` | — | ArgoCD GitOps |
| `argo-rollouts` | baseline | Progressive delivery |
| `authentik` | restricted | Identity provider |
| `cert-manager` | baseline | TLS certificates |
| `cilium-secrets` | — | Cilium internal |
| `cnpg-system` | restricted | PostgreSQL operator |
| `cloudflared` | — | Cloudflare tunnel |
| `dns` | privileged | DNS (CoreDNS + etcd + external-dns) |
| `external-secrets` | baseline | Secret sync |
| `falco` | privileged | Runtime security |
| `kube-system` | — | Kubernetes system + Cilium |
| `kyverno` | baseline | Policy engine |
| `local-path-storage` | privileged | Storage provisioner |
| `minio` | baseline | S3-compatible object storage |
| `monitoring` | — | Prometheus, Grafana, Loki, etc. |
| `platform` | baseline | Gateway API gateway |
| `tailscale` | privileged | Tailscale operator |
| `velero` | baseline | Backup/DR |

### Key URLs (all private, Tailscale-only)

| URL | Service | Auth |
|-----|---------|------|
| `argocd.platform.nqlabs.network` | ArgoCD | OIDC |
| `grafana.platform.nqlabs.network` | Grafana | OIDC |
| `auth.platform.nqlabs.network` | Authentik | — |
| `prometheus.platform.nqlabs.network` | Prometheus | Forward-auth |
| `alertmanager.platform.nqlabs.network` | Alertmanager | Forward-auth |
| `rollouts.platform.nqlabs.network` | Argo Rollouts Dashboard | Forward-auth |
| `uptime.platform.nqlabs.network` | Uptime Kuma | Forward-auth |
| `hubble.platform.nqlabs.network` | Hubble UI | Forward-auth |

### Key IP Addresses

| IP | Purpose |
|----|---------|
| `192.168.15.31` | Management cluster node |
| `192.168.15.32` | Staging cluster node |
| `192.168.15.33` | Production cluster node |
| `192.168.15.192` | CoreDNS LoadBalancer |
| `192.168.15.195` | Platform Gateway LoadBalancer |
| `100.120.180.12` | CoreDNS Tailscale IP (split DNS) |

### Related Documents

- [Architecture: Service Factory](service-factory.md)
- [Decision: Cluster Topology](../decisions/cluster-topology.md)
- [Decision: DNS Architecture](../decisions/dns-architecture.md)
- [Decision: IP Address Plan](../decisions/ip-address-plan.md)
- [Decision: Identity Provider](../decisions/identity-provider.md)
- [Runbook: SSO & Authentik](../runbooks/sso-authentik.md)
- [Runbook: Backup & Velero](../runbooks/backup-velero.md)
- [Runbook: Secrets Management](../runbooks/secrets.md)
- [Runbook: ArgoCD Bootstrap](../runbooks/argocd-bootstrap.md)
- [Runbook: Onboarding a New Application](../runbooks/onboarding-a-new-application.md)
- [Runbook: Preview Environments](../runbooks/preview-environments.md)
- [Runbook: Cluster & Edge Operations](../runbooks/cluster-and-edge-operations.md)
- [Runbook: Remote Cluster Service Factory](../runbooks/remote-cluster-service-factory.md)
- [Runbook: Public Edge (Cloudflare)](../runbooks/public-edge-cloudflare.md)
- [Roadmap](../roadmap.md)
