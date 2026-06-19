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


## Target repository boundary

The long-term target is that this repository contains **platform architecture,
SRE/infrastructure, cluster lifecycle, reusable platform charts, policies, runbooks,
and educational material only**.

Application source code should live in application-owned repositories. A service repo
owns its app code, tests, Dockerfile, and GitHub Actions release workflow. That
workflow should build/publish the image and then trigger the GitOps delivery path
(for example by opening a PR against the appropriate deployment source or calling an
ArgoCD sync/refresh mechanism that still preserves auditable desired state).

Initial external app repository reserved for this migration:

```text
NicolasQueiroga/nqlabs-demo  # private; GitHub Actions enabled with read/write workflow permissions
```

This platform repository may contain temporary bootstrap/demo material while the
service factory and release model are being proven, but that material must not become
permanent product code. When the architecture is complete enough to operate from the
new model, clean the repository so it contains exactly what the platform needs and no
more:

- keep cluster inventory, Talos patches, ArgoCD platform apps, infra manifests,
  reusable charts, Terraform/OpenTofu platform onboarding modules, docs, runbooks,
  guides, and scripts;
- remove or migrate app source/build contexts such as `services/demo/` to their own
  service repositories;
- remove or convert example app environment contracts under `apps/` if the final
  model points ArgoCD directly at external service repos;
- keep only minimal examples/templates if they teach or validate the platform and are
  explicitly labeled as examples.

The cleanup itself is a platform milestone. Do not let proof/demo files silently
become production structure.

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

Desktop multi-cluster rehearsal folders:

```text
clusters/desktop-lab/        # active one-cluster substrate validation
clusters/nqlabs-management/  # planned management/platform cluster
clusters/nqlabs-staging/     # planned staging workload cluster
clusters/nqlabs-production/  # planned production workload cluster
```

NUC-era folders should preserve the same cluster names unless there is a deliberate
rename decision. The NUCs are a hardware migration of the desktop-rehearsed topology,
not a separate architecture.

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

Current bootstrap/demo service environment contracts.

Example:

```text
apps/demo/environments/staging.yaml
apps/demo/environments/production.yaml
```

These files are not application source code. They are declarative deployment
contracts consumed by the current service ApplicationSet proof path.

Target direction: real applications should live in their own repositories, including
their source code and release workflow. If the final multi-repo model has ArgoCD read
service deployment state directly from those repositories, `apps/` should be removed
or reduced to explicitly labeled examples/templates during the repo cleanup milestone.

Until that migration happens, files under `apps/` are bootstrap contracts only. They
should not become a dumping ground for product/application ownership.

## `services/`

Temporary first-party demo service source/build contexts.

Example:

```text
services/demo/Dockerfile
services/demo/index.html
```

This exists to prove the service factory and release automation. It is not the
long-term application ownership model. Real applications should have their own
repositories with their own GitHub Actions workflows. After the multi-repo delivery
model is proven, migrate demo/product code out of this repository or keep only a
minimal explicitly labeled example.

Rule of thumb:

```text
Architecture, SRE, infrastructure, and reusable platform tooling belong here.
Application/product code belongs in application repositories.
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
