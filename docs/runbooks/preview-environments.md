# Runbook — Preview environments (per-PR ephemeral previews)

Every application pull request can get a throwaway preview environment on demand,
with a **1 hour TTL** so previews never leak resources.

## Developer interface (PR comments)

| Comment | Effect |
|---|---|
| `/preview deploy [--workers] [--scheduler]` | Build + deploy a preview (1h TTL). For multi-workload apps, workers/scheduler are off unless flagged (api/web only by default). |
| `/preview renew` | Extend the TTL by another hour. |
| `/preview destroy` | Tear the preview down now. |
| `/preview status` | Report the preview URL and expiry. |

Plus automatic behavior:
- **New commit on the PR** → the active preview rebuilds and updates (same URL, TTL preserved).
- **PR closed/merged** → the preview is torn down.
- **TTL**: ~10 min before expiry the reaper comments a warning suggesting `/preview renew`; if ignored, the preview is automatically destroyed at expiry.

Only `OWNER`/`MEMBER`/`COLLABORATOR` commenters can run `/preview`.

## URL + placement

```
host:       <app>-pr-<number>.staging.nqlabs.network
cluster:    nqlabs-staging          (previews reuse the staging cluster)
namespace:  <app>-pr-<number>
image tag:  pr-<number>-<shortsha>
```

Previews intentionally use the `*.staging.nqlabs.network` wildcard so they reuse
the existing staging cert, Cilium Gateway, and HAProxy edge — **no preview-specific
infrastructure is required**.

## How it works (GitOps)

```
/preview deploy (PR comment in app repo)
  → app repo caller workflow calls the platform reusable preview workflow
  → build + push image  ghcr.io/<owner>/<app>:pr-<n>-<sha>
  → write apps/<app>/previews/pr-<n>.yaml in nqlabs-platform (expiresAt = now+1h)
  → commit to platform main
  → the `previews` ApplicationSet generates an ephemeral ArgoCD Application
  → ArgoCD deploys it to nqlabs-staging, namespace <app>-pr-<n> (CreateNamespace)
  → comment the URL back on the PR

reaper (cron */5, app repo caller → platform reusable reaper)
  → scan apps/<app>/previews/pr-*.yaml
  → ~10 min before expiresAt: comment a warning once
  → at/after expiresAt: git rm the descriptor → ApplicationSet prunes the app + namespace
```

### Components

Platform repo (`nqlabs-platform`):
- `clusters/nqlabs-management/argocd/apps/projects.yaml` → `services-preview` AppProject (staging cluster, `*-pr-*` namespaces).
- `clusters/nqlabs-management/services/manifests/previews-applicationset.yaml` → the `previews` ApplicationSet (reads `apps/*/previews/*.yaml`).
- `.github/workflows/preview-reusable.yaml` → command/auto-update/teardown logic (reusable, `app`-agnostic).
- `.github/workflows/preview-reaper-reusable.yaml` → TTL warn/teardown logic (reusable).

Application repo (e.g. `nqlabs-demo`):
- `.github/workflows/preview.yaml` → thin caller (`uses:` the platform reusable, sets `app`/`image`).
- `.github/workflows/preview-reaper.yaml` → thin caller (schedule).

Descriptors are built and edited with `yq`; TTL math uses `date`. No helper scripts.

## Operating notes

- A preview descriptor is a normal service descriptor (`charts/nqlabs-service` values)
  plus a `preview:` block (`number`, `sha`, `expiresAt`, `warnedAt`). Do not edit by hand.
- The reaper runs every 5 minutes from each app repo and comments on that repo's own
  PRs with its own `GITHUB_TOKEN` (no cross-repo token needed).
- Tearing down = removing the descriptor file; ArgoCD prune + the namespace's owned
  resources are removed automatically.

## Adding the preview lane to a new app

See [onboarding-a-new-application.md](onboarding-a-new-application.md). In short: copy
the two thin caller workflows into the new app repo and set `app`/`image`.
