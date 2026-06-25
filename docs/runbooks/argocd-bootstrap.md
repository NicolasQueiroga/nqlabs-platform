# Runbook: ArgoCD Bootstrap

> **Status:** Live three-cluster service factory (management/staging/production). Current architecture: [../docs/architecture/service-factory.md](../docs/architecture/service-factory.md). Single-cluster/desktop-lab references below are historical.


## Overview

This runbook covers the one-time manual bootstrap of ArgoCD on the lab cluster.
After bootstrap, the root Application discovers all platform Applications from git,
including the `argocd` self-management Application. From that point forward,
`clusters/nqlabs-management/argocd/values.yaml` is authoritative for ArgoCD itself.

## Prerequisites

- Talos cluster running and `kubectl` configured
- Cilium installed and node `Ready`
- `helm` CLI installed
- `clusters/nqlabs-management/argocd/` committed and pushed to GitHub
- 1Password service account token (see [secrets.md](secrets.md))

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
  -f clusters/nqlabs-management/argocd/values.yaml
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
`clusters/nqlabs-management/argocd/apps/argocd.yaml`, which makes ArgoCD manage its own Helm release.

```bash
kubectl apply -f clusters/nqlabs-management/argocd/apps/root.yaml
```

Verify it synced:

```bash
kubectl get applications -n argocd
# Expected: root   Synced   Healthy
```

## Step 3a — Create the 1Password service account token secret

ESO needs a 1Password service account token to read secrets from the `NQLabs` vault.
This is the trust root for all platform secrets and must be applied manually before
the root Application can sync ESO-dependent apps (authentik, minio, velero, etc.).

```bash
# Create the bootstrap secret in the external-secrets namespace
kubectl -n external-secrets create secret generic onepassword-service-account-token \
    --from-literal=token=<your-1password-service-account-token>
```

See [secrets.md](secrets.md) for how to generate a new token and rotate it.

## Step 4 — Wait for 0-to-100 bootstrap

After applying the root Application and the 1Password token, ArgoCD will begin
syncing all 60+ platform Applications automatically. The sync follows the
`argocd.argoproj.io/sync-wave` annotations to order dependencies correctly.

Watch the progress:

```bash
# Watch all applications sync
kubectl get applications -n argocd -w

# Check overall health
argocd app list -o wide
```

Expected progression (sync waves):

1. **Wave 0-1:** Cilium, cert-manager, external-secrets, local-path, tailscale
2. **Wave 2:** Kyverno, gateway, CoreDNS, external-dns
3. **Wave 3:** Kyverno policies, Authentik, monitoring stack
4. **Wave 4+:** MinIO, Velero, Loki, Tempo, Pyroscope, Gatus, demo services

All applications should reach `Synced` and `Healthy` within ~15-20 minutes on a
fresh cluster. If any app is stuck, see the Troubleshooting section below.

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
| nqlabs-management | 192.168.15.31 | 192.168.15.31 |
| nqlabs-staging | 192.168.15.32 | 192.168.15.32 |
| nqlabs-production | 192.168.15.33 | 192.168.15.33 |

Install Cilium with both value files so cluster identity stays declarative:

```bash
helm template prometheus-operator-crds \
  prometheus-community/prometheus-operator-crds \
  --version 29.0.0 \
  | kubectl apply --server-side=true -f -

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.19.4 \
  -f infrastructure/networking/cilium/values.yaml \
  -f clusters/<cluster>/cilium/values.yaml
```

On current single-node VMs, `operator.replicas=1`. Raise to `2` only after the
NUC/HA cluster has multiple schedulable nodes.

## Adding new platform services

Once ArgoCD is running, add new Application manifests to `clusters/nqlabs-management/argocd/apps/`.
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
clusters/nqlabs-management/argocd/apps/
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

**cert-manager webhook not reachable (cert-manager pods CrashLoopBackOff)**
- The `cert-manager-deny-ingress` NetworkPolicy blocks API server admission calls
  to the webhook. A CiliumNetworkPolicy (`cert-manager-allow-kube-apiserver-webhook`)
  allows `host`, `remote-node`, and `kube-apiserver` entities on port 10250.
- Same pattern is used for external-secrets webhook.

**Gatus CrashLoopBackOff (OIDC issuer unreachable)**
- Gatus uses the internal Authentik service URL
  (`http://authentik-server.authentik.svc.cluster.local:80/...`) for the OIDC
  `issuer-url` because the Cilium gateway resets TLS connections from pods
  (hairpin issue with LoadBalancer IP).
- Browser-based OIDC login will redirect to the internal URL, which is a known
  limitation until the Cilium gateway hairpin issue is resolved.

**MinIO bucket creation Job fails**
- The PostSync Job waits up to 5 minutes for MinIO to be ready before creating
  buckets. If MinIO takes longer to start, increase the retry count in the job
  command.
- Ensure the `minio-auth` secret (from ESO) is available before the job runs.

**Kyverno policies show `OutOfSync`**
- Kyverno defaults several fields on ClusterPolicy at admission time
  (`admission`, `emitWarning`, `validationFailureAction`, etc.). These are
  listed in `ignoreDifferences` in the ArgoCD Application.
- The `disallow-host-path` policy uses a `deny` condition (not `pattern` with
  `X()`) because Kyverno transforms the `X(hostPath): null` pattern to `{}`,
  which breaks the validation and causes perpetual OutOfSync.
