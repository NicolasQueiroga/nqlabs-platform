# Runbook: ArgoCD Bootstrap

> **Status:** Point-zero platform template. Management cluster only (3-node Talos
> on Proxmox). Staging and production clusters will be provisioned later by
> management onto separate hardware.

## Overview

This runbook covers the one-time manual bootstrap of ArgoCD on the management
cluster. After bootstrap, the root Application discovers all platform
Applications from git, including the `argocd` self-management Application.
From that point forward, `platform/argocd/values.yaml` is authoritative for
ArgoCD itself.

## Prerequisites

- Talos cluster running and `kubectl` configured
- Cilium installed and nodes `Ready`
- `helm` CLI installed
- `clusters/nqlabs-management/` committed and pushed to GitHub
- 1Password service account token (see [secrets.md](secrets.md))

## Step 1 — Add Helm repo

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
```

## Step 2 — Install ArgoCD (bootstrap values)

Use the bootstrap values file — it enables the admin user and omits
`extraObjects` (which require ESO CRDs that don't exist yet). After GitOps
installs ESO and the full ArgoCD app syncs, it switches to the production
values at `platform/argocd/values.yaml` (SSO via Authentik, admin disabled).

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f clusters/nqlabs-management/bootstrap/argocd-bootstrap.yaml
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

## Step 3 — Get admin password and access the UI

```bash
# Get the initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Port-forward to access the ArgoCD UI locally:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open: https://localhost:8080 (accept the self-signed cert)

Login: `admin` / `<password from above>`

After the Gateway and DNS stack are synced, the durable URL is:

```text
https://argocd.platform.nqlabs.network
```

## Step 4 — Create the 1Password service account token secret

ESO needs a 1Password service account token to read secrets from the `NQLabs`
vault. This is the trust root for all platform secrets and must be applied
manually before the root Application can sync ESO-dependent apps (authentik,
minio, velero, etc.).

```bash
# Create the namespace first (ESO will be installed into it by GitOps)
kubectl create namespace external-secrets

# Create the bootstrap secret from 1Password CLI
op item get "Service Account Auth Token: NQ Labs" \
  --account my.1password.com --fields credential --format json \
  | python3 -c "import json,sys; sys.stdout.write(json.load(sys.stdin)['value'])" \
  | kubectl -n external-secrets create secret generic onepassword-service-account-token \
      --from-file=token=/dev/stdin
```

See [secrets.md](secrets.md) for how to generate a new token and rotate it.

## Step 5 — Apply AppProjects (BEFORE root Application)

The root Application references `project: platform` but ArgoCD can't sync it
until the AppProject exists. This is a chicken-and-egg problem — apply the
AppProjects manually first.

```bash
kubectl apply -f clusters/nqlabs-management/argocd/apps/projects.yaml
```

Verify:

```bash
kubectl get appprojects -n argocd
# Minimum required for bootstrap: platform
# Additional service projects may exist, but remote-cluster fan-out is enabled later.
```

## Step 6 — Apply the root Application (triggers 0-to-100 GitOps sync)

This is the seed of the app-of-apps pattern. Applied once, manually.
After this, all platform additions are git commits. The root app will also
discover `clusters/nqlabs-management/argocd/apps/argocd.yaml`, which makes
ArgoCD manage its own Helm release.

```bash
kubectl apply -f clusters/nqlabs-management/argocd/root.yaml
```

Verify it synced:

```bash
kubectl get applications -n argocd
# Expected: root   Synced   Healthy
```

## Step 7 — Wait for 0-to-100 bootstrap

After applying the root Application, ArgoCD will begin syncing the
**management-cluster platform stack only**. The sync follows the
`argocd.argoproj.io/sync-wave` annotations to order dependencies correctly.

In practice, "0-to-100" means **all management-cluster apps** reach
`Synced` + `Healthy` with no manual intervention after the steps above.
Staging/production foundation apps and the service-factory fan-out are
intentionally excluded from the initial root Application and are enabled later,
after the management cluster is fully healthy and Authentik-backed access is in
place.

Watch the progress:

```bash
# Watch all applications sync
kubectl get applications -n argocd -w

# Check which apps are NOT yet Synced+Healthy
kubectl get applications -n argocd -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data['items']:
    name = item['metadata']['name']
    sync = item['status']['sync']['status']
    health = item['status']['health']['status']
    if sync != 'Synced' or health != 'Healthy':
        print(f'{name:45s} {sync:12s} {health}')
"
```

Expected progression (sync waves):

1. **Wave 0-1:** Cilium, cert-manager, external-secrets, local-path, tailscale
2. **Wave 2:** Kyverno, gateway, CoreDNS, external-dns
3. **Wave 3:** Kyverno policies, Authentik, monitoring stack
4. **Wave 4+:** MinIO, Velero, Loki, Tempo, Pyroscope, Gatus, demo services

All management applications should reach `Synced` and `Healthy` within
~15-20 minutes on a fresh cluster.

If any app is stuck, see the Troubleshooting section below.

## Step 8 — Rotate the admin password

After the bootstrap is complete and SSO via Authentik is working, rotate the
admin password and delete the initial secret:

```bash
# Login to the UI, then change the password:
# Settings → Account → Update Password

# After rotating, delete the initial secret
kubectl -n argocd delete secret argocd-initial-admin-secret
```

## Cluster-specific values

| Cluster | VIP | k8sServiceHost |
|---------|-----|----------------|
| nqlabs-management | 192.168.15.9 | 192.168.15.9 |
| nqlabs-staging | (future) | (future) |
| nqlabs-production | (future) | (future) |

Install Prometheus CRDs and Cilium before ArgoCD:

```bash
helm template prometheus-operator-crds \
  prometheus-community/prometheus-operator-crds \
  --version 29.0.0 \
  | kubectl apply --server-side=true -f -

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.19.4 \
  -f infrastructure/networking/cilium/values.yaml \
  -f clusters/<cluster>/cilium/values.yaml \
  --set hubble.metrics.serviceMonitor.enabled=false

# Wait for Cilium agent pods to be ready (label is k8s-app=cilium, not app.kubernetes.io/name)
kubectl -n kube-system wait --for=condition=ready pod -l k8s-app=cilium --timeout=120s
```

`hubble.metrics.serviceMonitor.enabled=false` is required at bootstrap because
the ServiceMonitor CRD may not be installed yet. Enable it later via GitOps once
kube-prometheus-stack is synced.

`--server-side=true` is required for the Prometheus CRDs because the
`kubectl.kubernetes.io/last-applied-configuration` annotation exceeds the 256KB
metadata limit on the large CRDs (alertmanagers, prometheuses, etc.).

## Adding new platform services

Once ArgoCD is running, add new Application manifests to `clusters/nqlabs-management/argocd/apps/`.
The root Application syncs that directory — any new file is picked up automatically.

Platform services must use:

```yaml
spec:
  project: platform
```

The `platform` AppProject allows only the platform repo plus approved upstream Helm
repositories, and only the platform namespaces used by this cluster. Remote-cluster
service delivery (`services-staging` / `services-production`) is enabled in a later
phase after management bootstrap is complete.

```
clusters/nqlabs-management/argocd/apps/
├── root.yaml                       # Root app — applied once manually
├── projects.yaml                   # AppProjects (platform required before root)
├── argocd.yaml                     # ArgoCD self-management
├── cert-manager.yaml               # cert-manager + issuers/certs
├── external-secrets-operator.yaml  # ESO + 1Password SDK config
└── ...
```

Remote-cluster manifests (staging foundation, production foundation,
service-factory, etc.) stay in git but are explicitly excluded from the initial
root Application until the later multi-cluster phase.

No `kubectl` or `helm install` needed for anything after bootstrap.

## Troubleshooting

**Root app shows `OutOfSync` or "app is not allowed in project"**
- The `platform` AppProject doesn't exist yet. Apply it first:
  `kubectl apply -f clusters/nqlabs-management/argocd/apps/projects.yaml`
- Then refresh the root app:
  `kubectl annotate app root -n argocd argocd.argoproj.io/refresh=normal`

**Root app shows `OutOfSync` (after projects applied)**
- Check if the commit on GitHub matches what ArgoCD shows
- Click `Refresh` in the UI or: `kubectl annotate app root -n argocd argocd.argoproj.io/refresh=normal`

**Staging / production / service-factory apps appear during bootstrap**
- They are intentionally deferred from the management bootstrap.
- Re-apply the updated root Application so its exclude list takes effect:
  `kubectl apply -f clusters/nqlabs-management/argocd/root.yaml`
- Then refresh root: `kubectl annotate app root -n argocd argocd.argoproj.io/refresh=hard --overwrite`

**Pod stuck in `Pending`**
- Check node resources: `kubectl describe pod <pod> -n <namespace>`
- Check if nodes are cordoned: `kubectl get nodes`
- Uncordon if needed: `kubectl uncordon mgmt-01 mgmt-02 mgmt-03`

**`argocd-server` not accessible via port-forward**
- Try `kubectl port-forward svc/argocd-server -n argocd 8080:443` for HTTPS
- Accept the self-signed certificate in the browser

**Namespaces stuck in `Terminating` after teardown**
- ArgoCD Application finalizers block deletion when the controller is gone.
- Remove finalizers from all Applications:
  `kubectl get applications.argoproj.io -n argocd -o name | xargs kubectl patch --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'`
- ExternalSecret finalizers also block — delete ESO validating webhooks first:
  `kubectl delete validatingwebhookconfiguration externalsecret-validate secretstore-validate`
  Then patch: `kubectl get externalsecrets.external-secrets.io -A -o name | xargs kubectl patch --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'`
- Then force-delete namespaces: `kubectl patch namespace <ns> --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'`
- Do **not** delete built-in ClusterRoles/ClusterRoleBindings such as
  `cluster-admin`, `admin`, `edit`, or `view` during teardown. Velero and
  other components rely on them before Authentik/SSO is fully established.

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
- Authentik must also be reachable from the `monitoring` namespace:
  - `authentik-allow-dns` must match the actual CoreDNS label (`k8s-app: coredns`,
    not `k8s-app: kube-dns`).
  - `authentik-server` needs an ingress allow from the `monitoring` namespace on
    pod port `9000` (service port `80` targets container port `9000`).
- If Gatus still crashes, confirm Authentik has endpoints:
  `kubectl get endpoints -n authentik authentik-server`
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

**Prometheus CRDs fail to apply (metadata.annotations too long)**
- Use `kubectl apply --server-side=true` instead of `kubectl apply`.
- The CRDs are too large for the `kubectl.kubernetes.io/last-applied-configuration`
  annotation (256KB limit).
