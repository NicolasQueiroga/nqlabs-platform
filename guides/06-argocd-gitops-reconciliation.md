# Guide 06 — ArgoCD and GitOps Reconciliation

> **Status:** NQLabs is now a live three-cluster service factory (management/staging/production). Current architecture: [../docs/architecture/service-factory.md](../docs/architecture/service-factory.md). Sections below describing single-cluster/laptop/desktop-lab stages are historical.


## Learning objectives

By the end of this guide, a student should be able to explain:

- what ArgoCD reconciles
- how the app-of-apps pattern works
- the difference between refresh, sync, prune, and self-heal
- why a resource can be successfully synced but still appear OutOfSync
- how controller-defaulted fields create false drift
- why ArgoCD now self-manages its own Helm release in this platform

## The core GitOps loop

ArgoCD continuously compares two worlds:

```text
git desired state  ⇄  live Kubernetes state
```

If they differ, ArgoCD reports drift. If automated sync is enabled, ArgoCD can apply
changes to make the live cluster match git.

The important sentence:

> GitOps is not just deployment. It is continuous comparison and correction.

## App-of-apps pattern

This platform uses one manually bootstrapped root Application:

```text
root Application
    ↓ watches
platform/argocd/apps/
    ↓ creates/manages
all platform Applications
```

The root Application is applied once:

```bash
kubectl apply -f platform/argocd/apps/root.yaml
```

After that, adding a platform component means adding an Application manifest under
`platform/argocd/apps/` and committing it.

Current important Applications include:

- `argocd` — ArgoCD self-management
- `gateway` — Cilium Gateway + HTTPRoutes
- `external-secrets` / `external-secrets-config`
- `kube-prometheus-stack` / `monitoring-config`
- `cert-manager` / `cert-manager-config`
- `coredns-dns`, `etcd-dns`, `external-dns`

## ArgoCD self-management

ArgoCD was bootstrapped manually with Helm, but now manages itself through:

```text
platform/argocd/apps/argocd.yaml
platform/argocd/values.yaml
```

This matters because ArgoCD configuration itself — including global diff customization —
now lives in git and is reconciled by ArgoCD.

## Commands: inspect app health

List all apps:

```bash
kubectl get applications -n argocd
```

Check one app:

```bash
kubectl get application <app> -n argocd -o yaml
```

Show only resources not synced:

```bash
kubectl get application <app> -n argocd -o json | python3 -c '
import json, sys
app = json.load(sys.stdin)
for r in app.get("status", {}).get("resources", []):
    if r.get("status") != "Synced":
        print(r.get("kind"), r.get("name"), r.get("namespace", ""), r.get("status"))
'
```

## Refresh vs sync

A refresh asks ArgoCD to re-check git and live state:

```bash
kubectl annotate application <app> -n argocd \
  argocd.argoproj.io/refresh=normal --overwrite
```

A hard refresh also clears more cached comparison/rendering state:

```bash
kubectl annotate application <app> -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

A sync applies desired state to the cluster:

```bash
kubectl patch application <app> -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'
```

Use refresh when you want ArgoCD to re-evaluate. Use sync when you want ArgoCD to apply.

## Why sync can succeed but app stays OutOfSync

Some Kubernetes controllers default fields after a resource is applied.

Example: an `HTTPRoute` manifest may omit `backendRefs[].weight`. The Gateway API
controller defaults it to `1`. Git has no field; live state has `weight: 1`; ArgoCD
sees drift.

Same pattern with ESO `ExternalSecret` fields such as:

- `conversionStrategy`
- `decodingStrategy`
- `metadataPolicy`
- `nullBytePolicy`
- `deletionPolicy`

The resource is healthy. Sync succeeds. But comparison still reports OutOfSync unless
ArgoCD is told to ignore those controller-owned defaults.

## Global diff policy

This platform handles common defaulted fields globally in `platform/argocd/values.yaml`:

- Gateway API `HTTPRoute`
- Gateway API `Gateway`
- ESO `ExternalSecret`

That prevents every future app from needing repetitive `ignoreDifferences` blocks.

Verify the live config:

```bash
kubectl get configmap argocd-cm -n argocd \
  -o yaml | grep -A40 resource.customizations.ignoreDifferences
```

## AppProjects: ArgoCD's deployment boundary

An ArgoCD `Application` answers: "what should be deployed?"

An ArgoCD `AppProject` answers: "what is this Application allowed to do?"

Projects restrict:

- allowed source repositories
- allowed destination clusters/namespaces
- allowed cluster-scoped resource kinds
- allowed namespace-scoped resource kinds

This matters because ArgoCD is powerful. A compromised or misconfigured Application
should not automatically be able to deploy anywhere in the cluster or create any
resource kind.

The platform currently uses three root-managed AppProjects:

| Project | Purpose |
|---------|---------|
| `platform` | Current infrastructure and platform controllers: ArgoCD, cert-manager, DNS, Gateway, ESO, observability, Rollouts, Tailscale, storage |
| `services-staging` | Future staging service workloads; namespace-scoped resources only |
| `services-production` | Future production service workloads; namespace-scoped resources only |

All current platform Applications use:

```yaml
spec:
  project: platform
```

Future generated service Applications should use `services-staging` or
`services-production`, not `platform` and not the built-in `default` project.

Check project assignment:

```bash
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,PROJECT:.spec.project,SYNC:.status.sync.status,HEALTH:.status.health.status
```

Check project definitions:

```bash
kubectl get appprojects -n argocd
kubectl get appproject platform -n argocd -o yaml
```

## Debugging exact ArgoCD diffs

When `kubectl diff` says clean but ArgoCD says OutOfSync, inspect ArgoCD's managed
resource states.

The API endpoint is:

```text
/api/v1/applications/<app>/managed-resources
```

The useful fields are:

- `targetState` — rendered desired state from git/Helm/Kustomize
- `normalizedLiveState` — live Kubernetes state after ArgoCD normalization

Compare those to find which field is causing drift.

## Checkpoint questions

1. What is the difference between refresh and sync?
2. Why can a sync operation succeed while the app remains OutOfSync?
3. Why is a global diff policy better than repeating per-app ignores for HTTPRoutes?
4. Why should ArgoCD self-manage after bootstrap?
5. What does an AppProject restrict that an Application alone does not?
6. Why should generated service Applications avoid the `platform` project?
7. If `kubectl diff` is clean but ArgoCD is OutOfSync, what should you inspect next?
