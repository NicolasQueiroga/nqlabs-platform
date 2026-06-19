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
| Secrets Backend (Phase 0–1) | 1Password SDK provider + service account token |
| Secrets Backend (Phase 2) | [OpenBao](https://openbao.org/) — self-hosted OSS Vault fork |

### Storage
| Layer | Technology |
|-------|-----------|
| Storage (Phase 0) | local-path-provisioner |
| Storage (Phase 1+) | [Rook/Ceph](https://rook.io/) — block, filesystem, and object storage |
| Backup | [Velero](https://velero.io/) |

### Observability
| Layer | Technology |
|-------|-----------|
| Metrics | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) — Prometheus + Grafana + Alertmanager |
| Logging | [Loki](https://grafana.com/oss/loki/) + Promtail |
| Tracing (Phase 2) | [Grafana Tempo](https://grafana.com/oss/tempo/) + [OpenTelemetry Collector](https://opentelemetry.io/) |

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
├── .github/workflows/     # CI/release automation
├── clusters/              # Per-cluster bootstrap (Talos configs, ArgoCD install)
│   └── lab/               # Local development cluster (laptop/VM)
├── infrastructure/        # Platform services managed by ArgoCD
│   ├── networking/        # Cilium, Gateway API, external-dns
│   ├── storage/           # local-path (Phase 0), Rook/Ceph (Phase 1)
│   ├── monitoring/        # Prometheus, Grafana, Alertmanager, Loki/Promtail
│   ├── security/          # cert-manager, External Secrets, Kyverno, Falco, Harbor
│   └── identity/          # OpenBao, SSO, workload identity (Phase 2)
├── platform/
│   └── argocd/            # ArgoCD itself — app-of-apps root
├── apps/                  # Service environment contracts consumed by ApplicationSet
├── services/              # Build contexts for first-party service images
├── terraform/             # Service/product onboarding definitions and modules
├── docs/
│   ├── decisions/         # Architecture Decision Records (ADRs)
│   └── runbooks/          # Operational procedures
├── guides/                # Educational curriculum for understanding the platform
└── scripts/               # Bootstrap and utility scripts
```

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
All sensitive values are stored in 1Password and injected at runtime
via [External Secrets Operator](https://external-secrets.io/).

See `.gitignore` for the full exclusion list.

## Phases

| Phase | Target | Status |
|-------|--------|--------|
| 0 — Foundation | Single-node Talos on Mac laptop (UTM/ARM64) | 🔧 In progress — core platform operational, readiness backlog remains |
| 0.7 — Fixed-IP Desktop Lab | Ryzen 9 7950X / 124GB RAM Proxmox/Talos VM host; active Proxmox VM storage is currently 130GB thin LVM | ⏳ Planned virtualized NUC architecture rehearsal |
| 1 — NUC Cluster | Dell NUC-class three-cluster private cloud | ⏳ Planned bare-metal implementation of the rehearsed topology |
| 2 — Operations | Full automation, DR, multi-cluster | ⏳ Planned |

Current IP plan and migration notes: [`docs/decisions/ip-address-plan.md`](./docs/decisions/ip-address-plan.md)

Cluster topology decision: [`docs/decisions/cluster-topology.md`](./docs/decisions/cluster-topology.md)

Service namespace model: [`docs/decisions/service-namespace-model.md`](./docs/decisions/service-namespace-model.md)

The environment progression is:

```text
Mac laptop / UTM lab → desktop virtualized NUC rehearsal → NUC bare-metal private cloud
```

Target cluster model:

```text
nqlabs-management
nqlabs-staging
nqlabs-production
```
