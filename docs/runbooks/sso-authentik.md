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
| Prometheus, Alertmanager, Uptime Kuma, Argo Rollouts | Forward-auth (embedded proxy outpost) | any authenticated user in a bound group |

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

## Secrets (1Password → ESO)

| 1Password item | Fields | Used by |
|----------------|--------|---------|
| `authentik` | secret_key, bootstrap_password, bootstrap_token, redis_password | Authentik server/worker |
| `authentik-postgres` | password | CNPG cluster + Authentik |
| `argocd-oidc` | client_secret | ArgoCD oidc.config + Authentik blueprint (!Env) |
| `grafana-oidc` | client_secret | Grafana auth.generic_oauth + Authentik blueprint (!Env) |

The first admin user is `akadmin`; its password is `authentik/bootstrap_password`.

## Onboarding a user

1. Log into `https://auth.platform.nqlabs.network` as `akadmin`.
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
1Password item + ESO key), then configure the app's OIDC client.

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
- **API token** for scripting: `authentik/bootstrap_token` (Bearer).
- **Outpost health:** `GET /api/v3/outposts/instances/` — the embedded outpost
  should list the proxy provider PKs and a recent `last_seen`.
- **Gotcha:** Authentik blueprint `!Env` tags need a default — `!Env [VAR, ""]`,
  not `!Env [VAR]` (the single-element form crashes the YAML loader).

## Verification

```bash
# OIDC apps redirect to Authentik
curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://grafana.platform.nqlabs.network/login/generic_oauth
# Forward-auth apps redirect to the outpost
curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://prometheus.platform.nqlabs.network/
# -> 302 .../outpost.goauthentik.io/start?rd=...
```
