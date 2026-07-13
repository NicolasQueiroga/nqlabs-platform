# SSO & Identity (Authentik)

How platform authentication works and how to operate it. Decision/architecture:
[../decisions/identity-provider.md](../decisions/identity-provider.md).

## Overview

**Authentik** (`auth.platform.nqlabs.network`) is the single identity provider.
Every platform UI authenticates against it:

| UI | Method | Access |
|----|--------|--------|
| ArgoCD | OIDC (native) | group → role: `platform-admins`=admin, `platform-viewers`=readonly |
| Grafana | OIDC (native) | `platform-admins`=Admin, else Viewer |
| Prometheus, Alertmanager, Gatus, Argo Rollouts, Thanos, Pyroscope | Forward-auth (embedded proxy outpost) | any authenticated user in a bound group |

Data layer: CloudNativePG (`authentik-pg`) + Valkey (`authentik-valkey`) in the
`authentik` namespace on the management cluster.

## Components (all GitOps)

- `clusters/nqlabs-management/argocd/apps/cloudnative-pg.yaml` — Postgres operator
- `clusters/nqlabs-management/argocd/apps/authentik.yaml` — Authentik app (Helm + manifests + blueprints)
- `infrastructure/identity/authentik/` — values, manifests, blueprints, kustomization
- OIDC wiring: `platform/argocd/values.yaml` (configs.cm/rbac/extraObjects),
  `infrastructure/monitoring/kube-prometheus-stack/values.yaml` (grafana.ini),
  `infrastructure/monitoring/externalsecrets.yaml` (grafana-oidc)
- Forward-auth routing: `infrastructure/monitoring/routes.yaml`,
  `infrastructure/delivery/argo-rollouts/dashboard-route/`,
  `infrastructure/identity/authentik/manifests/referencegrant.yaml`

## Secrets (OpenBao → ESO)

| OpenBao item | Fields | Used by |
|----------------|--------|---------|
| `authentik-login` | secret_key, bootstrap_password, bootstrap_token, redis_password | Authentik server/worker |
| `authentik-postgres` | password | CNPG cluster + Authentik |
| `argocd-oidc` | client_secret | ArgoCD oidc.config + Authentik blueprint (!Env) |
| `grafana-oidc` | client_secret | Grafana auth.generic_oauth + Authentik blueprint (!Env) |
| `gatus-oidc` | client_secret | Gatus OIDC config + Authentik blueprint (!Env) |

The canonical day-0 platform admin user is `nicolas`; its password is
`authentik-login/bootstrap_password`.

`akadmin` is still created by Authentik's upstream bootstrap flow as a fallback
instance admin, but platform access policies are designed around the declarative
`nicolas` user in `platform-admins`.

## Onboarding a user

1. Log into `https://auth.platform.nqlabs.network` as `nicolas`.
2. **Directory → Users → Create** (or connect a federated source later).
3. Add the user to a group:
   - `platform-admins` — full admin across all UIs.
   - `platform-viewers` — read-only.
4. The user can now log into every platform UI with one identity. Removing them
   from the group (or disabling the user) revokes access everywhere.

Groups are defined declaratively in
`infrastructure/identity/authentik/blueprints/10-groups.yaml`. Add new groups
there and map them to roles in the consuming app (ArgoCD `policy.csv`, Grafana
`role_attribute_path`).

## Adding a new app to SSO

**OIDC-native app:** add an `oauth2provider` + `application` entry to
`blueprints/20-oidc.yaml` (fixed `client_id`, secret via `!Env` from a new
OpenBao item + ESO key), then configure the app's OIDC client.

**Non-OIDC app (forward-auth):**
1. Add a `proxyprovider` (mode: proxy, `external_host`, `internal_host`) +
   `application` to `blueprints/30-proxy.yaml`, and add it to the embedded
   outpost `providers` list.
2. Point the app's HTTPRoute `backendRefs` at `authentik-server.authentik:80`.
3. If the route is in a new namespace, add it to the `from` list of the
   `ReferenceGrant` in `manifests/referencegrant.yaml`, and make sure the
   backend namespace's NetworkPolicy allows the `authentik` namespace.

## Operations

- **Blueprints** reconcile automatically (mounted ConfigMap, discovered by the
  worker). After editing, sync the `authentik` app; the worker re-applies within
  ~minutes. Force: `kubectl exec -n authentik deploy/authentik-worker -- ak apply_blueprint /blueprints/mounted/cm-authentik-blueprints/<file>.yaml`.
- **API token** for scripting: `authentik-login/bootstrap_token` (Bearer).
- **Outpost health:** `GET /api/v3/outposts/instances/` — the embedded outpost
  should list the proxy provider PKs and a recent `last_seen`.
- **Gotcha:** Authentik blueprint `!Env` tags need a default — `!Env [VAR, ""]`,
  not `!Env [VAR]` (the single-element form crashes the YAML loader).

## Break-glass access (when Authentik is down)

Forward-auth protected services (Prometheus, Alertmanager, Rollouts, Gatus,
Thanos, Pyroscope) depend on Authentik being up. If Authentik is down, use
kubectl port-forward to bypass the gateway and auth layer:

```bash
# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Access at http://localhost:9090

# Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Access at http://localhost:9093

# Grafana (OIDC, but still works with local admin if configured)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Access at http://localhost:3000

# Argo Rollouts dashboard
kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100
# Access at http://localhost:3100

# Gatus
kubectl port-forward -n monitoring svc/gatus 8081:8081
# Access at http://localhost:8081
```

For OIDC services (ArgoCD, Grafana), local admin login is disabled — SSO via
Authentik is the only login method. When Authentik is down, use kubectl
port-forward to access services directly (bypassing the gateway and auth).

**ArgoCD break-glass (admin disabled):**
```bash
# Port-forward the ArgoCD server
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Access at https://localhost:8080

# To re-enable the admin user temporarily:
kubectl patch configmap argocd-cm -n argocd --type=merge -p '{"data":{"accounts.admin.enabled":"true"}}'
# Then restart the ArgoCD server:
kubectl rollout restart deploy/argocd-server -n argocd
# Get the admin password:
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.admin\.password}' | base64 -d
```

**Grafana break-glass (login form disabled):**
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Access at http://localhost:3000

# The local admin user still exists in the grafana-admin-credentials secret.
# To login via port-forward, temporarily re-enable the login form:
kubectl patch configmap kube-prometheus-stack-grafana -n monitoring --type=merge \
  -p '{"data":{"grafana.ini":{"auth":{"disable_login_form":"false","oauth_auto_login":"false"}}}}'
# Then restart Grafana:
kubectl rollout restart deploy/kube-prometheus-stack-grafana -n monitoring
# Get the admin password:
kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

## CNPG backup & restore

Authentik PostgreSQL is backed up via CloudNativePG's native backup mechanism.
WAL files are archived continuously to Ceph RGW (`s3://authentik-pg/wal`), and a
scheduled full backup runs daily at 02:00 UTC (`ScheduledBackup` CR).

### Check backup status

```bash
# List recent backups
kubectl get backups.postgresql.cnpg.io -n authentik
# Check WAL archiving status
kubectl describe cluster authentik-pg -n authentik | grep -A5 "WAL Archiving"
# Check the scheduled backup CR
kubectl get scheduledbackup authentik-pg-daily -n authentik
```

### Restore from backup

```bash
# 1. (Optional) Point-in-time recovery — restore to a specific timestamp
kubectl apply -n authentik -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: authentik-pg-restored
spec:
  bootstrap:
    recovery:
      backup:
        name: <backup-name>
      targetTime: "2026-01-15T10:30:00+00:00"
  storage:
    storageClass: local-path
    size: 5Gi
EOF

# 2. Full restore from latest backup
kubectl apply -n authentik -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: authentik-pg-restored
spec:
  bootstrap:
    recovery:
      backup:
        name: <backup-name>
  storage:
    storageClass: local-path
    size: 5Gi
EOF

# 3. Once restored, update Authentik to point at the new cluster:
#    kubectl patch deployment authentik-server -n authentik \
#      --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"authentik-pg-restored-rw"}]'
#    Or update the values.yaml postgresql.host and sync the ArgoCD app.
```

## Verification

```bash
# OIDC apps redirect to Authentik
curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://grafana.platform.nqlabs.network/login/generic_oauth
# Forward-auth apps redirect to the outpost
curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://prometheus.platform.nqlabs.network/
# -> 302 .../outpost.goauthentik.io/start?rd=...
```
