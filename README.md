# NQLabs Platform

A Kubernetes-native private cloud platform. Fully self-hosted, declarative, and production-grade.

> Kubernetes is the infrastructure abstraction layer.

## What this is

NQLabs Platform is a private cloud operating environment built to provide capabilities
traditionally associated with public cloud providers — compute orchestration, storage,
networking, identity, observability, and automated delivery — while remaining entirely
self-hosted and operator-controlled.

This repository is the **single source of truth** for all platform state.
If it is not in this repository, it does not exist.

## Design Principles

- **Kubernetes-first** — orchestration, not VMs
- **Declarative** — desired state in code, Git as the authority
- **Private by default** — public exposure is an intentional exception
- **Automation over repetition** — manual procedures are a temporary state
- **Resilience by design** — failure is a normal operating condition
- **Production-grade** — no home-lab shortcuts

## Stack

### Foundation
| Layer | Technology |
|-------|-----------|
| Operating System | [Talos Linux](https://www.talos.dev/) — immutable, API-driven, Kubernetes-native |
| Orchestration | Kubernetes |
| GitOps | [ArgoCD](https://argo-cd.readthedocs.io/) — app-of-apps pattern |
| VPN / Access | [Tailscale](https://tailscale.com/) + Tailscale Operator |

### Networking
| Layer | Technology |
|-------|-----------|
| CNI | [Cilium](https://cilium.io/) — eBPF, kube-proxy replacement, Hubble observability |
| Ingress / Routing | [Cilium Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/) — Gateway API spec, no separate controller |
| Certificate Management | [cert-manager](https://cert-manager.io/) |

### Secret Management
| Layer | Technology |
|-------|-----------|
| Secrets Operator | [External Secrets Operator](https://external-secrets.io/) |
| Secrets Backend (Phase 0–1) | OpenBao KV + service account token |
| Secrets Backend (future) | [OpenBao](https://openbao.org/) — self-hosted OSS Vault fork |

### Storage
| Layer | Technology |
|-------|-----------|
| Storage (Phase 0) | local-path-provisioner |
| Distributed Storage | [Rook/Ceph](https://rook.io/) — block, filesystem, and object storage |
| Backup | [Velero](https://velero.io/) |

### Observability
| Layer | Technology |
|-------|-----------|
| Metrics | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) — Prometheus + Grafana + Alertmanager |
| Logging | [Loki](https://grafana.com/oss/loki/) + Promtail |
| Tracing | [Grafana Tempo](https://grafana.com/oss/tempo/) + [OpenTelemetry Collector](https://opentelemetry.io/) |

### Security
| Layer | Technology |
|-------|-----------|
| Policy Enforcement | [Kyverno](https://kyverno.io/) — admission control, policy-as-code |
| Runtime Security | [Falco](https://falco.org/) — eBPF syscall-level anomaly detection |
| Container Registry | [Harbor](https://goharbor.io/) — OCI registry + proxy cache + vulnerability scanning |
| Vulnerability Scanning | [Trivy](https://trivy.dev/) — integrated into Harbor |
| Supply Chain | [Cosign](https://docs.sigstore.dev/cosign/overview/) — image signing and verification |

## Domains

| Domain | Purpose |
|--------|---------|
| `nqlabs.io` | Public-facing services, DNS managed by Cloudflare |
| `nqlabs.network` | Internal services (Tailscale-gated only) |

Internal naming convention:

| Pattern | Purpose | Example |
|---------|---------|---------|
| `<service>.platform.nqlabs.network` | Singleton platform tools | `argocd.platform.nqlabs.network` |
| `<service>.staging.nqlabs.network` | Staging application services | `api.staging.nqlabs.network` |
| `<service>.production.nqlabs.network` | Production application services in the private Mac/desktop/NUC platform network | `api.production.nqlabs.network` |

Use `production`, never `prod`, in DNS names and environment labels.

Current platform endpoints:

- `https://argocd.platform.nqlabs.network`
- `https://grafana.platform.nqlabs.network`
- `https://prometheus.platform.nqlabs.network`
- `https://alertmanager.platform.nqlabs.network`

## Repository Structure

Detailed structure documentation: [`docs/repo-structure.md`](./docs/repo-structure.md)

```
nqlabs-platform/
├── .github/workflows/        # platform CI (validate) + reusable preview workflows
├── clusters/
│   ├── nqlabs-management/     # management cluster: ArgoCD app-of-apps + service factory  (CANONICAL)
│   ├── nqlabs-staging/        # staging cluster: Talos patches + foundation
│   └── nqlabs-production/     # production cluster: Talos patches + foundation
├── infrastructure/           # platform services managed by ArgoCD
│   ├── networking/           # Cilium, Gateway API, Tailscale operator/connector/coredns
│   ├── storage/              # local-path now, Rook/Ceph later
│   ├── monitoring/           # Prometheus, Grafana, Alertmanager, Loki/Promtail
│   ├── security/             # cert-manager, External Secrets + OpenBao ClusterSecretStore
│   └── identity/             # Authentik SSO IdP (CloudNativePG + Valkey) + OIDC/forward-auth
├── charts/nqlabs-service/    # reusable service chart (single- or multi-workload)
├── apps/<app>/               # deployment contracts: environments/*.yaml + previews/*.yaml
├── terraform/                # optional service scaffolding (writes descriptors)
├── docs/
│   ├── architecture/         # service-factory architecture
│   ├── decisions/            # Architecture Decision Records (ADRs)
│   └── runbooks/             # operational procedures
├── guides/                   # educational curriculum
└── scripts/                  # bootstrap and utility scripts
```

## Service delivery (the service factory)

The platform deploys applications through a descriptor-driven, multi-cluster GitOps
service factory: management ArgoCD generates one Application per
`apps/<app>/environments/*.yaml` and deploys it to the named environment cluster.
Merges deploy staging; releases promote production; PR comments create previews.

- Architecture: [`docs/architecture/service-factory.md`](./docs/architecture/service-factory.md)
- Add a new app (plug-and-play): [`docs/runbooks/onboarding-a-new-application.md`](./docs/runbooks/onboarding-a-new-application.md)
- Preview environments: [`docs/runbooks/preview-environments.md`](./docs/runbooks/preview-environments.md)
- Cluster access / recovery / edge: [`docs/runbooks/cluster-and-edge-operations.md`](./docs/runbooks/cluster-and-edge-operations.md)

## Learning Track

The [`guides/`](./guides/) folder is the educational track for this platform. It is
designed so a computer engineering / computer science student can learn how to reason
about, configure, operate, and troubleshoot the system.

Guides are intentionally different from runbooks:

- **Runbooks** give exact operational procedures.
- **Guides** teach mental models, ask checkpoint questions, and provide guided labs.

The goal is not to hide information. The goal is to avoid training operators to blindly
copy commands they do not understand.

## Security

This is a public repository. Secrets are **never** committed here.
All sensitive values are stored in OpenBao KV and injected at runtime
via [External Secrets Operator](https://external-secrets.io/).

See `.gitignore` for the full exclusion list.

## Phases

| Phase | Target | Status |
|-------|--------|--------|
| 0 — Foundation | Single-node Talos on Mac laptop (UTM/ARM64) | 🔧 In progress — core platform operational, readiness backlog remains |
| 0.7 — Fixed-IP Desktop Full Architecture | Ryzen 9 7950X / 124GB RAM Proxmox/Talos VM host | ✅ Three-cluster architecture live — `nqlabs-management` (VM131), `nqlabs-staging` (VM132), `nqlabs-production` (VM133); service factory + previews operational. (Legacy desktop-lab VM 130 removed.) |
| 1 — Hardware Node Expansion | Dell NUC-class node pool | ⏳ Add/replace nodes in the desktop-proven architecture; no new platform capabilities are gated here |
| 2 — Operations/Security Hardening | Same architecture, starting on desktop | ⏳ Buildable on desktop after multi-cluster baseline; not NUC-gated |

Current IP plan and migration notes: [`docs/decisions/ip-address-plan.md`](./docs/decisions/ip-address-plan.md)

Cluster topology decision: [`docs/decisions/cluster-topology.md`](./docs/decisions/cluster-topology.md)

Service namespace model: [`docs/decisions/service-namespace-model.md`](./docs/decisions/service-namespace-model.md)

The environment progression is:

```text
Mac laptop / UTM lab → desktop full architecture on Proxmox VMs → NUCs added as bare-metal nodes/capacity
```


The desktop phase is not blocked by the NUCs. The desktop has enough CPU/RAM to run
`nqlabs-management`, `nqlabs-staging`, and `nqlabs-production` as Talos VM clusters.
NUCs later add bare-metal nodes/capacity to the same architecture; they should not
introduce new platform capabilities or a separate design.

Target cluster model:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```
