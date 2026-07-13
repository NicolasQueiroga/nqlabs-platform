# Repository Structure

This repository is the source of truth for the NQLabs Platform. If a platform
component, service contract, workflow, or operational decision is not represented
here, treat it as unmanaged state.

It separates four concerns: cluster bootstrap, platform infrastructure, service
delivery contracts, and education/operations documentation.

```text
nqlabs-platform/
├── .github/workflows/        # platform CI (validate) + reusable preview workflows
├── clusters/
│   ├── nqlabs-management/     # management cluster: ArgoCD app-of-apps + Talos patches  (CANONICAL)
│   ├── nqlabs-staging/        # staging cluster: Talos patches + foundation
│   └── nqlabs-production/     # production cluster: Talos patches + foundation
├── infrastructure/           # platform capabilities (CNI, DNS, gateway, secrets, monitoring, delivery, tailscale)
├── charts/
│   └── nqlabs-service/        # reusable service chart (single- or multi-workload)
├── apps/
│   └── <app>/
│       ├── environments/      # staging.yaml / production.yaml deployment descriptors
│       └── previews/          # ephemeral per-PR preview descriptors (auto-managed)
├── terraform/                 # optional service scaffolding (writes descriptors; Git/ArgoCD still deploy)
├── docs/
│   ├── architecture/          # target + current-state architecture
│   ├── decisions/             # durable design records
│   └── runbooks/              # exact operational procedures
├── guides/                    # educational curriculum
└── scripts/                   # bootstrap/utility scripts
```

## Platform vs application boundary

The platform repo owns **deployment state and reusable platform tooling**, not
product source. Application source, Dockerfiles, and release workflows live in
application repositories (e.g. `NicolasQueiroga/nqlabs-demo`). The platform repo
holds only the declarative descriptors that say *what runs where*. See
[onboarding-a-new-application.md](runbooks/onboarding-a-new-application.md).

## `clusters/`

Per-cluster bootstrap + the management app-of-apps.

- `clusters/nqlabs-management/argocd/` — the **canonical** app-of-apps. `root.yaml`
  watches `clusters/nqlabs-management/argocd/apps`, which defines the platform
  Applications, the AppProjects (`platform`, `services-staging`, `services-production`,
  `services-preview`), and the service-factory wiring.
- `clusters/nqlabs-management/services/manifests/` — the service factory: the
  descriptor-driven `services` ApplicationSet and the `previews` ApplicationSet.
- `clusters/nqlabs-{staging,production}/` — Talos control-plane patches and the
  remote foundation (Cilium LB IPAM, gateway).

Talos `generated/` material is gitignored; secrets live in OpenBao, never in git.

## `infrastructure/`

Platform capabilities managed by ArgoCD Applications (not application services):
`networking/` (Cilium, Gateway API, **Tailscale** operator/connector/coredns),
`dns/`, `security/` (cert-manager, External Secrets + the OpenBao ClusterSecretStore),
`monitoring/`, `delivery/` (Argo Rollouts), `storage/`, `identity/`, `observability/`.

Rule of thumb: *if it is needed to run the platform itself, it belongs in `infrastructure/`.*

## `charts/nqlabs-service/`

The standard rendering path for service workloads. Supports:

- single workload (legacy top-level values) **or** a multi-workload `workloads:` map
  (api/web/worker/scheduler, each a Deployment or Argo Rollout)
- Service, internal/public/preview HTTPRoutes, ServiceAccount
- probes, HorizontalPodAutoscaler, PodDisruptionBudget, ServiceMonitor, ExternalSecret
- secure-by-default pod/container security contexts (opt-out per workload)
- `values.schema.json` to reject invalid descriptors before ArgoCD renders them

## `apps/`

Declarative deployment **contracts** consumed by the ApplicationSets — not source code.

```text
apps/<app>/environments/staging.yaml      # cluster-aware: argocd.destination.name + namespace <app>
apps/<app>/environments/production.yaml
apps/<app>/previews/pr-<n>.yaml           # ephemeral, written by the preview workflow
```

Each descriptor names its destination cluster (`nqlabs-staging` / `nqlabs-production`)
and project; the `services` ApplicationSet generates one Application per file
(automatic scale — no central list to edit).

## `.github/workflows/`

- `validate.yaml` — platform CI: helm lint + helm-template every descriptor (enforces
  `values.schema.json`) + kubeconform + GitOps YAML parse + actionlint.
- `preview-reusable.yaml` / `preview-reaper-reusable.yaml` — reusable, app-agnostic
  preview lane workflows that application repos call.

Application repos own their build/staging/release/preview *caller* workflows.

## `docs/` and `guides/`

`docs/architecture/` (target + current state), `docs/decisions/` (durable records),
`docs/runbooks/` (exact procedures). `guides/` is the educational curriculum
(mental models, reasoning, failure modes). A platform capability is not complete
until its operator-facing documentation exists and matches the running system.

## `terraform/`

Optional service scaffolding. It writes descriptors under `apps/<service>/environments/`;
Git and ArgoCD remain the deployment path. Terraform never deploys to Kubernetes directly.

## Completion rule

Avoid undocumented implicit state. The goal is a platform that can be rebuilt,
operated, extended, audited, and taught from git.
