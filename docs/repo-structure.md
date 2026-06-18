# Repository Structure

This repository is the source of truth for the NQLabs Platform. If a platform
component, service contract, workflow, or operational decision is not represented
here, it should be treated as unmanaged state.

The structure separates four concerns:

1. cluster bootstrap
2. platform infrastructure
3. service delivery contracts
4. education and operations documentation

```text
nqlabs-platform/
├── .github/workflows/
├── clusters/
│   └── lab/
├── infrastructure/
│   ├── delivery/
│   ├── dns/
│   ├── identity/
│   ├── monitoring/
│   ├── networking/
│   ├── observability/
│   ├── security/
│   └── storage/
├── platform/
│   ├── argocd/
│   └── services/
├── apps/
├── services/
├── terraform/
├── charts/
├── docs/
│   ├── decisions/
│   └── runbooks/
├── guides/
└── scripts/
```

## `.github/workflows/`

CI and release automation.

Current workflow:

```text
.github/workflows/release-service.yaml
```

This workflow builds first-party service images from `services/<service>`, pushes
them to GHCR, and opens a pull request updating the corresponding environment file
under `apps/<service>/environments/`.

Full GitHub Actions hardening, required checks, repository rules, and branch
protection are tracked as future work. They are not discarded.

## `clusters/`

Per-cluster bootstrap state.

Current cluster:

```text
clusters/lab/
```

This folder contains laptop/VM bootstrap material for the Phase 0 Talos cluster.
It should not contain plaintext Talos secrets. Secrets belong in 1Password or a
future self-hosted secret backend.

Future clusters should get their own folders, for example:

```text
clusters/desktop-lab/
clusters/nuc-production/
clusters/nuc-staging/
```

## `infrastructure/`

Platform infrastructure managed by ArgoCD Applications.

This is for platform capabilities, not application services.

| Directory | Purpose |
|-----------|---------|
| `delivery/` | Progressive delivery components such as Argo Rollouts |
| `dns/` | standalone CoreDNS, etcd DNS backend, external-dns |
| `identity/` | future SSO/workload identity services |
| `monitoring/` | Prometheus, Grafana, Alertmanager, Blackbox, Loki, Promtail |
| `networking/` | Cilium, Gateway API, Tailscale networking |
| `observability/` | future tracing/OpenTelemetry/Tempo work |
| `security/` | cert-manager, External Secrets, future Kyverno/Falco/Harbor |
| `storage/` | local-path now, Rook/Ceph later |

Rule of thumb:

```text
If it is needed to run the platform itself, it belongs in infrastructure/.
```

## `platform/`

Higher-order platform control-plane resources.

Current areas:

```text
platform/argocd/
platform/services/
```

`platform/argocd/` contains the app-of-apps root and child ArgoCD Applications.

`platform/services/` contains the service factory bootstrap: the ApplicationSet that
generates service Applications from `apps/*/environments/*.yaml`. Service namespaces
are created by the generated Applications with `CreateNamespace=true`.

Rule of thumb:

```text
If it tells ArgoCD how to manage the platform, it belongs in platform/.
```

## `apps/`

Service environment contracts.

Example:

```text
apps/demo/environments/staging.yaml
apps/demo/environments/production.yaml
```

These files are not application source code. They are declarative deployment
contracts consumed by the service ApplicationSet.

They define:

- service name
- target environment
- target namespace
- ArgoCD project
- Helm values file path
- image repository/tag
- route hostname
- rollout/service settings

Rule of thumb:

```text
If changing it should cause ArgoCD to deploy or update a service environment,
it belongs in apps/.
```

## `services/`

First-party service source/build contexts.

Example:

```text
services/demo/Dockerfile
services/demo/index.html
```

The release workflow builds images from here and pushes them to GHCR. The workflow
then opens a PR against `apps/<service>/environments/<environment>.yaml`.

Rule of thumb:

```text
If it is app code or image build input, it belongs in services/.
```

## `charts/`

Reusable Helm charts owned by the platform.

Current chart:

```text
charts/nqlabs-service/
```

This chart is the standard rendering path for service workloads. It currently
supports ServiceAccount, Service, HTTPRoute, Deployment, and Argo Rollouts Rollout.

## `terraform/`

Higher-level service/product onboarding definitions.

Current module:

```text
terraform/modules/nqlabs-service/
```

Current service definition:

```text
terraform/services/demo/
```

Terraform does not deploy directly to Kubernetes. It writes service environment
files under `apps/<service>/environments/`; Git and ArgoCD remain the deployment
path.

Rule of thumb:

```text
If it defines a product/service contract above raw Helm values, it belongs in terraform/.
```

## `docs/`

Operational and architectural documentation.

| Directory | Purpose |
|-----------|---------|
| `docs/decisions/` | durable architecture decisions and design records |
| `docs/runbooks/` | exact operational procedures |

Docs are part of the platform. A platform capability is not complete until the
operator-facing documentation exists and matches the running system.

## `guides/`

Educational curriculum.

Guides teach mental models, reasoning, validation, and failure modes. They are not
just command lists. Runbooks are for execution; guides are for understanding.

## `scripts/`

Bootstrap and utility scripts.

Scripts should be safe to re-run when possible and should not embed secrets.

Current examples:

```text
scripts/install-gateway-api-crds.sh
scripts/update-service-image.py
```

## Completion rule

This repository should avoid undocumented implicit state. The goal is not “mostly
working.” The goal is a platform that can be rebuilt, operated, extended, audited,
and taught from git.
