# Runbook — Onboarding a new application (plug-and-play)

The platform is designed so a brand-new application gets **staging, production, and
previews** with no bespoke infrastructure. The deploy machinery is generic; a new
app contributes only declarative descriptors plus thin caller workflows.

This runbook is the canonical "how to add an app" path.

---

## What the platform provides (so you don't rebuild it)

- A reusable service chart: `charts/nqlabs-service` (single- or multi-workload).
- A descriptor-driven `services` ApplicationSet that deploys any `apps/<app>/environments/*.yaml`
  to the correct cluster by **name** (`nqlabs-staging` / `nqlabs-production`).
- A `previews` ApplicationSet for any `apps/<app>/previews/*.yaml`.
- Reusable GitHub workflows for staging deploy, production promotion, and previews.
- AppProjects (`services-staging`, `services-production`, `services-preview`) and the
  HAProxy/Tailscale edge that already routes `*.staging` / `*.production` / `*.platform`.

A new app needs **no** new AppProject, ApplicationSet, gateway, cert, DNS, or edge rule.

---

## 1. Application repository

Create `<owner>/<app>` with:

- application source + `Dockerfile`
- CI workflows — copy from `templates/app-workflows/` in the platform repo and replace `<app>`/`<owner>`:
  - `build.yaml` — PR build validation (no push)
  - `deploy-staging-on-main.yaml` — on merge to `main`, calls the platform `deploy-reusable` workflow which builds, pushes `sha-<commit>`, and updates the staging descriptor
  - `release-please.yaml` — manages versioning via release PRs; on merge creates a GitHub Release + tag
  - `promote-production-on-release.yaml` — on GitHub Release, calls the platform `deploy-reusable` workflow which promotes the exact staged artifact and opens a production PR
  - `preview.yaml` — thin caller for `/preview deploy|renew|destroy|status` commands
  - `preview-reaper.yaml` — scheduled TTL reaper for expired previews

All workflows are thin callers that delegate to platform reusable workflows. The app repo only needs to set the `service` and `image` parameters — the platform handles build, push, descriptor updates, and supply chain security.

### Required repo secrets

| Secret | Scope | Purpose |
|---|---|---|
| `NQLABS_PLATFORM_REPO_TOKEN` | fine-grained PAT on `nqlabs-platform`: Contents RW, Pull requests RW, Metadata R | update/PR platform descriptors |
| `NQLABS_<APP>_RELEASE_TOKEN` | fine-grained PAT on the app repo: Contents RW, Pull requests RW, Metadata R | release-please tags/releases |

Also grant the app repo **Actions write access** to its GHCR package the first time.

---

## 2. Platform repository — descriptors only

### Fastest: the `Create application` workflow

Run the platform repo's **Create application** workflow (`workflow_dispatch`) with
`name`, `repository`, `image`, `port`, and `public`. It scaffolds the descriptors
and opens a PR — production gets a progressive canary by default.

### Or by hand: identity + environments

The platform side is split into stable identity and per-environment runtime:

```
apps/<app>/app.yaml                    # identity, exposure intent, default shape, dependencies
apps/<app>/environments/staging.yaml   # runtime: image tag, namespace, cluster, route host
apps/<app>/environments/production.yaml
```

`app.yaml` is merged UNDER each environment file before rendering the chart, so the
env files carry only what changes per environment. Declare dependencies in `app.yaml`:

```yaml
# app.yaml (excerpt)
dependencies:
  secrets:
    - envVar: DATABASE_URL
      remoteRef: { key: <app>/staging/database-url }   # materialized via External Secrets
config:
  LOG_LEVEL: info                                       # non-secret env via ConfigMap
```

Minimum environment descriptor:

```yaml
app:
  name: <app>
environment:
  name: staging                 # or production
  namespace: <app>              # the cluster is the environment boundary
argocd:
  project: services-staging     # services-production for prod
  valueFile: apps/<app>/environments/staging.yaml
  destination:
    name: nqlabs-staging        # nqlabs-production for prod
image:
  repository: ghcr.io/<owner>/<app>
  tag: sha-xxxxxxxxxxxx
container:
  port: 8080
route:
  enabled: true
  host: <app>.staging.nqlabs.network
# Hardened security contexts are ON by default; relax only if the image needs it:
# podSecurityContext: { enabled: false }
# securityContext:    { enabled: false }
```

Multi-component apps use a `workloads:` map instead of the top-level `image`/`route`
(see `charts/nqlabs-service/values.yaml`):

```yaml
workloads:
  api:    { kind: rollout, container: { port: 8080 }, routes: { internal: { enabled: true, host: <app>.staging.nqlabs.network } } }
  worker: { kind: deployment, command: [<app>, worker] }
```

Commit. The `services` ApplicationSet generates the Applications automatically.

---

## 3. Delivery model (what happens after onboarding)

```
PR to app repo            → build/test only (+ optional /preview deploy)
merge to app main         → build image, update staging descriptor → ArgoCD deploys staging
release PR → vX.Y.Z tag   → promote the exact staged artifact → production platform PR → merge → ArgoCD deploys production (canary)
```

- Internal `*.network` routes are private (Tailscale split DNS + DNS-01 TLS).
- Public `*.io` routes require an explicit, reviewed change and a public edge — never added by a routine image bump.

---

## 4. Exposure / namespace conventions

| Concern | Convention |
|---|---|
| staging host | `<app>.staging.nqlabs.network` |
| production host | `<app>.production.nqlabs.network` |
| preview host | `<app>-pr-<n>.staging.nqlabs.network` |
| namespace | `<app>` (per environment cluster); previews use `<app>-pr-<n>` |
| image | `ghcr.io/<owner>/<app>` (`sha-<commit>` staging, `vX.Y.Z` production, `pr-<n>-<sha>` preview) |

That is the whole onboarding. The platform scales to many applications without
editing any central list.
