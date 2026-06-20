# NQLabs Demo Deploy Flow — From Code Change to ArgoCD / Rollout

Generated: 2026-06-20

This document describes how the NQLabs demo service moves from code changes in the
application repository to deployed Kubernetes workloads in the staging and
production Talos clusters.

It is intentionally written as an operator mental model, not just a list of
commands. The goal is that a new service owner can understand exactly what
changes, where it changes, and why deployment only happens after GitOps state is
changed in the platform repository.

It covers:

- repository responsibilities
- PR/build path
- staging deploy proposal path
- production release proposal path
- what GitHub Actions do
- what changes in GitOps
- what management ArgoCD applies
- what happens in Kubernetes
- where preview environments would fit later
- current operational gaps and next improvements

---

## 0. Important terminology

### Application repository

The demo application code lives in:

```text
NicolasQueiroga/nqlabs-demo
```

This repo owns:

- application source
- Dockerfile / container build
- GitHub Actions build and release automation
- release tags / GitHub Releases
- artifact creation

It does **not** own runtime desired state for clusters.

### Platform / GitOps repository

Runtime Kubernetes desired state lives in:

```text
NicolasQueiroga/nqlabs-platform
```

For the demo service specifically:

```text
apps/demo/environments/
  staging.yaml
  production.yaml
```

The platform repo owns:

- environment descriptors
- reusable service chart
- ArgoCD ApplicationSets
- cluster destinations
- route hostnames
- rollout strategy
- quotas, policies, and operational defaults

### Reconciler

Management ArgoCD runs in the `nqlabs-management` cluster and watches
`nqlabs-platform`.

It generates and reconciles service Applications into the remote clusters:

| Environment | Cluster | API server | Environment file | Gateway IP |
|---|---|---:|---|---:|
| staging | `nqlabs-staging` | `https://192.168.15.32:6443` | `apps/demo/environments/staging.yaml` | `192.168.15.196` |
| production | `nqlabs-production` | `https://192.168.15.33:6443` | `apps/demo/environments/production.yaml` | `192.168.15.198` |

### Deploy trigger

A deployment is triggered by merging a PR in the platform repo that changes a
declarative environment descriptor.

The application repo builds artifacts. The platform repo declares what should run.
ArgoCD reconciles clusters from Git.

---

## 1. Current GitHub Actions files involved

### PR build workflow

```text
.github/workflows/build.yaml
```

Intended triggers:

```yaml
on:
  pull_request:
    branches:
      - main
  workflow_dispatch:
```

Purpose:

- validate that the demo container builds
- do not push an image for every PR by default
- do not create platform deploy PRs
- do not deploy previews automatically

PRs are validation-only until a future opt-in preview lane exists.

### Staging proposal workflow

```text
.github/workflows/deploy-staging-on-main.yaml
```

Trigger:

```yaml
on:
  push:
    branches:
      - main
```

Purpose:

- build and push an immutable SHA-tagged image
- update the staging environment descriptor in a platform repo branch
- open a platform repo PR
- do **not** mutate clusters directly
- do **not** push directly to platform `main`

### Production proposal workflow

```text
.github/workflows/promote-production-on-release.yaml
```

Trigger:

```yaml
on:
  release:
    types:
      - published
```

Purpose:

- verify the release commit is on `main`
- verify the matching staged SHA image exists
- promote that exact artifact to the release tag
- update the production environment descriptor in a platform repo branch
- open a platform repo PR
- do **not** deploy production until that PR is merged

---

## 2. Pull request path — build validation, not deploy

When a developer opens or updates a PR against `nqlabs-demo:main`, the app repo
should validate that the container still builds.

### What happens on PR

```text
PR opened/synchronized
  → build workflow starts
  → checkout code
  → setup Docker Buildx
  → build container image locally in CI
  → fail early if Dockerfile/source is broken
```

### What does not happen on PR

The PR path does not currently:

```text
PR → preview namespace → preview URL
PR → staging deploy
PR → production deploy
PR → platform repo PR
```

Current rule:

```text
PR = validate only
```

That keeps the platform quiet and avoids creating disposable environments for
every tiny change.

---

## 3. Staging path — merge to app main proposes staging deploy

### Trigger

A push to `nqlabs-demo:main` triggers:

```text
.github/workflows/deploy-staging-on-main.yaml
```

### Job behavior

```text
push to main
  → checkout app repo
  → compute short SHA tag
  → build multi-arch image
  → push ghcr.io/nicolasqueiroga/nqlabs-demo:sha-<shortsha>
  → checkout nqlabs-platform
  → run nqlabs-platform/scripts/update-service-image.py for staging
  → open PR in nqlabs-platform
```

### Image tag format

```text
sha-<12-char-git-sha>
```

Example:

```text
ghcr.io/nicolasqueiroga/nqlabs-demo:sha-58c0e7ab0b31
```

### Platform PR effect

The staging PR changes only:

```text
apps/demo/environments/staging.yaml
```

Expected diff shape:

```diff
image:
  repository: ghcr.io/nicolasqueiroga/nqlabs-demo
- tag: sha-old
+ tag: sha-new
```

### Why staging does not deploy until PR merge

The app repo does not own deployment state. It proposes a state change.

Deployment trigger:

```text
merge platform staging PR
```

After merge, management ArgoCD sees the changed GitOps state and reconciles
`demo-staging` into `nqlabs-staging`.

---

## 4. What ArgoCD applies in staging

Management ArgoCD's `service-factory` generates a service Application from:

```text
apps/demo/environments/staging.yaml
```

The generated Application targets:

```text
server: https://192.168.15.32:6443
namespace: demo-staging
project: services-staging
```

The shared chart is:

```text
charts/nqlabs-service
```

Current staging route:

```text
demo.staging.nqlabs.network
```

Current gateway:

```text
nqlabs-staging platform-gateway
LoadBalancer IP: 192.168.15.196
```

Current workload behavior:

```text
Argo Rollout resource
replicas: 1
canary strategy enabled
```

For the demo app, the canary strategy is intentionally simple. Later production
services should use richer production canary steps and health gates.

---

## 5. Production path — GitHub Release proposes production deploy

Production is intentionally separate from staging.

### Trigger

Publishing a GitHub Release in `nqlabs-demo` triggers:

```text
.github/workflows/promote-production-on-release.yaml
```

### Production job behavior

```text
GitHub Release published
  → checkout app repo
  → verify release commit is on main
  → compute sha-<shortsha> source tag
  → verify staged source image exists
  → promote exact source image to release tag
  → checkout nqlabs-platform
  → run nqlabs-platform/scripts/update-service-image.py for production
  → open PR in nqlabs-platform
```

### Why production uses the staged artifact

Production should not mean:

```text
whatever was just rebuilt
```

Production should mean:

```text
this exact artifact, already built from main and validated in staging, was intentionally promoted
```

That is why production promotion verifies the SHA image exists and retags that
same artifact as the release tag.

Example:

```text
source:  ghcr.io/nicolasqueiroga/nqlabs-demo:sha-58c0e7ab0b31
release: ghcr.io/nicolasqueiroga/nqlabs-demo:v0.1.0
```

### Platform PR effect

The production PR changes only:

```text
apps/demo/environments/production.yaml
```

Expected diff shape:

```diff
image:
  repository: ghcr.io/nicolasqueiroga/nqlabs-demo
- tag: old-release-or-sha
+ tag: vX.Y.Z
```

Deployment trigger:

```text
merge platform production PR
```

---

## 6. What ArgoCD applies in production

Management ArgoCD's `service-factory` generates a service Application from:

```text
apps/demo/environments/production.yaml
```

The generated Application targets:

```text
server: https://192.168.15.33:6443
namespace: demo-production
project: services-production
```

Current production route:

```text
demo.production.nqlabs.network
```

Current gateway:

```text
nqlabs-production platform-gateway
LoadBalancer IP: 192.168.15.198
```

Current workload behavior:

```text
Argo Rollout resource
replicas: 1
canary strategy enabled
```

The platform has Argo Rollouts installed in production. Future production service
contracts should define safer canary steps than the current demo default.

---

## 7. End-to-end timelines

### Normal PR

```text
0. Developer opens PR to nqlabs-demo main
1. build workflow runs
2. Docker image build is validated
3. no image is pushed by default
4. no platform PR is created
5. no cluster deployment happens
```

### Merge to main / staging proposal

```text
0. PR merged to nqlabs-demo main
1. staging proposal workflow starts
2. workflow builds multi-arch image
3. workflow pushes sha-<shortsha> image to GHCR
4. workflow checks out nqlabs-platform
5. workflow updates apps/demo/environments/staging.yaml on a release branch
6. workflow opens a platform PR
7. operator reviews PR diff
8. operator merges PR
9. management ArgoCD detects platform main change
10. ArgoCD reconciles demo-staging to nqlabs-staging
11. Argo Rollouts updates the demo pod
12. route should serve the new image at demo.staging.nqlabs.network
```

### GitHub Release / production proposal

```text
0. staging artifact has been built and deployed through staging PR
1. operator publishes GitHub Release in nqlabs-demo
2. production proposal workflow starts
3. workflow verifies release commit is on main
4. workflow verifies sha-<shortsha> image exists
5. workflow retags exact staged artifact as release tag
6. workflow checks out nqlabs-platform
7. workflow updates apps/demo/environments/production.yaml on a release branch
8. workflow opens a platform PR
9. operator reviews PR diff
10. operator merges PR
11. management ArgoCD detects platform main change
12. ArgoCD reconciles demo-production to nqlabs-production
13. Argo Rollouts updates production workload
14. route should serve the release image at demo.production.nqlabs.network
```

---

## 8. Preview path — not first-class yet

NQLabs does not yet have a preview environment lane.

Current PR behavior:

```text
PR → build validation only
```

Recommended future model:

```text
PR comment: /preview deploy
  → build preview image
  → create/update ephemeral ArgoCD Application
  → deploy preview namespace
  → comment preview URL

new commits while preview exists
  → auto-update preview

PR comment: /preview destroy
  → destroy preview

PR closed
  → destroy preview

scheduled cleanup
  → remove stale previews
```

Suggested future naming:

```text
app:       demo-pr-<number>
namespace: demo-pr-<number>
image:     pr-<number>-<shortsha>
host:      demo-pr-<number>.preview.nqlabs.network
```

Do not create previews for every PR by default. Previews should be opt-in so the
lab does not accumulate stale namespaces, routes, and workloads.

---

## 9. Important operational notes

### App repo does not deploy directly

The app repo does not call `kubectl`, does not call ArgoCD sync, and does not
mutate cluster runtime state.

It only builds artifacts and proposes platform repo PRs.

### Git is the deployment source of truth

Rollback should be Git-driven:

```text
revert platform PR
```

or:

```text
open a new platform PR setting image tag back to previous artifact
```

### Platform repo owns descriptor mutation

The demo repo does not carry a private YAML updater.

The workflows check out `nqlabs-platform` and run:

```bash
python3 scripts/update-service-image.py \
  --service demo \
  --environment staging|production \
  --repository ghcr.io/nicolasqueiroga/nqlabs-demo \
  --tag <tag>
```

This keeps the environment descriptor format owned by the platform repo.

### Staging and production are already cluster-separated

NQLabs uses the mature model from the start:

```text
staging cluster:    nqlabs-staging
production cluster: nqlabs-production
```

The service chart still uses environment-specific namespaces:

```text
demo-staging
demo-production
```

This is acceptable now. A future cleanup could simplify namespaces inside each
cluster to just `demo`, because cluster identity already separates environments.

### Known current gap: image digests

The current service descriptor uses image tags:

```yaml
image:
  repository: ghcr.io/nicolasqueiroga/nqlabs-demo
  tag: sha-...
```

Better future state:

```yaml
image:
  repository: ghcr.io/nicolasqueiroga/nqlabs-demo
  digest: sha256:...
```

Digest-based deploys are stronger because they are truly immutable.

### Known current gap: production canary strategy

The demo chart enables Argo Rollouts but currently uses a simple default canary
shape.

Future production services should define explicit production canary steps:

```text
0% traffic canary
manual pause
10%
manual pause
25%
manual pause
50%
manual pause
100%
```

---

## 10. Final mental model

```text
PR to app repo
  → validate build only

Merge to app main
  → build/push immutable image
  → open staging deploy PR in platform repo
  → merge platform PR
  → management ArgoCD deploys staging

GitHub Release in app repo
  → promote exact staged artifact
  → open production deploy PR in platform repo
  → merge platform PR
  → management ArgoCD deploys production
```

The app repo answers:

```text
what software artifact exists?
```

The platform repo answers:

```text
where and how should that artifact run?
```
