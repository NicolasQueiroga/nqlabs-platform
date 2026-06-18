# Runbook: ArgoCD Bootstrap

## Overview

This runbook covers the one-time manual bootstrap of ArgoCD on the lab cluster.
After bootstrap, the root Application discovers all platform Applications from git,
including the `argocd` self-management Application. From that point forward,
`platform/argocd/values.yaml` is authoritative for ArgoCD itself.

## Prerequisites

- Talos cluster running and `kubectl` configured
- Cilium installed and node `Ready`
- `helm` CLI installed
- `platform/argocd/` committed and pushed to GitHub

## Step 1 — Add Helm repo

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
```

## Step 2 — Install ArgoCD

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f platform/argocd/values.yaml
```

Watch pods come up (all should reach `Running` within ~60s):

```bash
kubectl get pods -n argocd -w
```

Expected pods:
- `argocd-application-controller-0`
- `argocd-applicationset-controller-*`
- `argocd-redis-*`
- `argocd-repo-server-*`
- `argocd-server-*`

## Step 3 — Bootstrap the root Application

This is the seed of the app-of-apps pattern. Applied once, manually.
After this, all platform additions are git commits. The root app will also discover
`platform/argocd/apps/argocd.yaml`, which makes ArgoCD manage its own Helm release.

```bash
kubectl apply -f platform/argocd/apps/root.yaml
```

Verify it synced:

```bash
kubectl get applications -n argocd
# Expected: root   Synced   Healthy
```

## Step 4 — Access the UI during bootstrap

Port-forward to access the ArgoCD UI locally:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Open: http://localhost:8080

Login: `admin` / (see Step 5)

After the Gateway and DNS stack are synced, the durable URL is:

```text
https://argocd.platform.nqlabs.network
```

## Step 5 — Retrieve and rotate the admin password

```bash
# Get the initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login to the UI, then immediately change the password:
**Settings → Account → Update Password**

After rotating, delete the initial secret:

```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
```

## Step 6 — Verify git sync

In the ArgoCD UI:
- `root` application should show `Synced` and `Healthy`
- `argocd` application should show `Synced` and `Healthy` after self-management syncs
- It should reference the latest commit on `main`

Current expected core apps after Phase 0 bootstrap:

```text
argo-rollouts
argocd
cert-manager
cert-manager-config
coredns-dns
etcd-dns
external-dns
external-secrets
external-secrets-config
gateway
kube-prometheus-stack
local-path-provisioner
loki
monitoring-config
promtail
root
tailscale-operator
```

Current expected AppProjects:

```text
platform
services-staging
services-production
```

All current platform Applications should use `project: platform`. The built-in
`default` project still exists because ArgoCD creates it automatically, but new
Applications should not use it.

## Cluster-specific values

| Cluster | Node IP | k8sServiceHost |
|---------|---------|----------------|
| lab (UTM laptop) | 192.168.64.3 | 192.168.64.3 |
| NUC cluster | TBD | TBD |

## Adding new platform services

Once ArgoCD is running, add new Application manifests to `platform/argocd/apps/`.
The root Application syncs that directory — any new file is picked up automatically.

Platform services must use:

```yaml
spec:
  project: platform
```

The `platform` AppProject allows only the platform repo plus approved upstream Helm
repositories, and only the platform namespaces used by this cluster. Future service
Applications should use `services-staging` or `services-production` instead of
`platform`.

```
platform/argocd/apps/
├── root.yaml                       # Root app — applied once manually
├── projects.yaml                   # AppProjects: platform, staging, production
├── argocd.yaml                     # ArgoCD self-management
├── cert-manager.yaml               # cert-manager + issuers/certs
├── external-secrets-operator.yaml  # ESO + 1Password SDK config
└── ...
```

No `kubectl` or `helm install` needed for anything after bootstrap.

## Troubleshooting

**Root app shows `OutOfSync`**
- Check if the commit on GitHub matches what ArgoCD shows
- Click `Refresh` in the UI or: `kubectl annotate app root -n argocd argocd.argoproj.io/refresh=normal`

**Pod stuck in `Pending`**
- Check node resources: `kubectl describe pod <pod> -n argocd`
- Single-node lab: all pods schedule on `talos-z9w-4rg`

**`argocd-server` not accessible via port-forward**
- Ensure `server.insecure: "true"` is set in values (HTTP mode)
- Try `kubectl port-forward svc/argocd-server -n argocd 8080:443` for HTTPS
