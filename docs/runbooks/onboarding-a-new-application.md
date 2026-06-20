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
- CI workflows (copy from `nqlabs-demo`, adjust `app`/`image`):
  - `build.yaml` — PR build validation
  - `deploy-staging-on-main.yaml` — on merge to `main`, build + push `sha-<commit>` and update the platform staging descriptor
  - `release-please.yaml` + `promote-production-on-release.yaml` — release PR → tag → production proposal PR (exact staged artifact)
  - `preview.yaml` + `preview-reaper.yaml` — thin callers to the platform reusable preview workflows:

    ```yaml
    # .github/workflows/preview.yaml
    on:
      issue_comment: { types: [created] }
      pull_request:  { types: [synchronize, closed] }
    permissions: { contents: read, packages: write, pull-requests: write }
    jobs:
      preview:
        uses: NicolasQueiroga/nqlabs-platform/.github/workflows/preview-reusable.yaml@main
        with:
          app: <app>
          image: ghcr.io/<owner>/<app>
        secrets: inherit
    ```

### Required repo secrets

| Secret | Scope | Purpose |
|---|---|---|
| `NQLABS_PLATFORM_REPO_TOKEN` | fine-grained PAT on `nqlabs-platform`: Contents RW, Pull requests RW, Metadata R | update/PR platform descriptors |
| `NQLABS_<APP>_RELEASE_TOKEN` | fine-grained PAT on the app repo: Contents RW, Pull requests RW, Metadata R | release-please tags/releases |

Also grant the app repo **Actions write access** to its GHCR package the first time.

---

## 2. Platform repository — descriptors only

Add per-environment descriptors (this is the entire platform-side change):

```
apps/<app>/environments/staging.yaml
apps/<app>/environments/production.yaml
```

Minimum descriptor:

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
