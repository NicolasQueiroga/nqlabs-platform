# Runbook — Cluster-aware Service Factory (named destinations)

How the NQLabs service factory deploys workloads from the **management** cluster
onto the remote **staging** and **production** clusters, addressing them by
**cluster name** (not server IP).

## Model

```text
management cluster (ArgoCD)
  └─ services ApplicationSet  (reads apps/*/environments/*.yaml)
       └─ one Application per service/environment
            project              = argocd.project            (services-staging | services-production)
            destination.name     = argocd.destination.name   (nqlabs-staging   | nqlabs-production)
            destination.namespace= environment.namespace      (plain service name, e.g. demo)
```

- Addressed by **cluster name**, so a cluster can change IP without editing the platform.
- The **cluster is the environment boundary** → namespaces use the plain service
  name (`demo`), not `demo-staging` / `demo-production`.
- One descriptor-driven ApplicationSet (automatic scale: adding a service = adding
  descriptor files only).

## Required cluster registration (names are load-bearing)

The descriptors, AppProjects, and ApplicationSet reference these ArgoCD cluster
**names**. The clusters MUST be registered in the **management** ArgoCD with
exactly these names or Applications fail with "cluster not found":

| Name | Cluster | API server (last known) |
|---|---|---|
| `nqlabs-staging` | staging | `https://192.168.15.32:6443` |
| `nqlabs-production` | production | `https://192.168.15.33:6443` |

### Register (or confirm) the names

```bash
# What is currently registered?
argocd cluster list

# If a cluster is registered under a different name (or only by server URL),
# re-add it with the exact name, or patch the cluster Secret's data.name.
argocd cluster add <staging-kube-context>    --name nqlabs-staging    --grpc-web
argocd cluster add <production-kube-context>  --name nqlabs-production  --grpc-web
```

To rename an existing cluster Secret in place (management `argocd` namespace):

```bash
# data.name is base64; set it to the required name
kubectl -n argocd get secret <cluster-secret> -o jsonpath='{.data.name}' | base64 -d   # inspect
kubectl -n argocd patch secret <cluster-secret> \
  --type merge -p "{\"data\":{\"name\":\"$(printf nqlabs-staging | base64)\"}}"
```

> Declarative option: register via an ExternalSecret that materializes the cluster
> Secret (labelled `argocd.argoproj.io/secret-type: cluster`) with a fixed `name`,
> pulling `server`/`caData`/`bearerToken` from 1Password. Keeps the name guaranteed
> by git.

## Migration note (applying this change to a live system)

This change switches the service factory from **server-IP destinations +
`<service>-<env>` namespaces** to **named destinations + plain `<service>`
namespaces**, and collapses two ApplicationSets into one. When ArgoCD reconciles:

1. The old `services-staging` / `services-production` ApplicationSets are replaced
   by a single `services` ApplicationSet. Generated Application names are unchanged
   (`demo-staging`, `demo-production`).
2. Each Application's destination namespace changes (`demo-staging` → `demo`), so
   the workload is recreated in the new namespace and the old namespace is pruned.
   Expect brief churn for affected services.

Recommended apply order:
1. Confirm `nqlabs-staging` / `nqlabs-production` are registered (above).
2. Merge this change.
3. Watch `kubectl -n argocd get applications` reconcile; confirm new `demo`
   namespaces come up Healthy and old `demo-staging`/`demo-production` are pruned.

## Verify

```bash
argocd cluster list | grep -E 'nqlabs-staging|nqlabs-production'

kubectl -n argocd get applications -o custom-columns=\
'NAME:.metadata.name,DEST-NAME:.spec.destination.name,NS:.spec.destination.namespace,SYNC:.status.sync.status,HEALTH:.status.health.status'
# Expected:
#   demo-staging      nqlabs-staging      demo   Synced  Healthy
#   demo-production   nqlabs-production   demo   Synced  Healthy
```

If an Application reports an unknown cluster, the descriptor's
`argocd.destination.name` does not match a registered ArgoCD cluster name.

## Adding a new service

1. Add `apps/<service>/environments/staging.yaml` and `production.yaml` with
   `environment.namespace: <service>`, `argocd.project`, and
   `argocd.destination.name`.
2. Commit. The ApplicationSet generates the Applications automatically.
3. The remote namespace is created automatically (`CreateNamespace=true`).
