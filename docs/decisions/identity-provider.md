# Identity Provider

Status: **LIVE** — Authentik is the platform identity provider for SSO and
forward-auth across all platform UIs.

## Decision

NQLabs uses **Authentik** as the single identity provider (IdP) for the platform.
All human access to platform UIs authenticates against Authentik, which is the
source of truth for users and groups. Two integration patterns are used depending
on whether the target application speaks OIDC:

| Application | OIDC-native | Integration |
|-------------|-------------|-------------|
| ArgoCD, Grafana | yes | Direct **OIDC** — the app redirects to Authentik; group claims map to in-app roles (RBAC) |
| Prometheus, Alertmanager, Argo Rollouts, Gatus, Hubble, Thanos, Pyroscope | no | **Forward-auth** via the Authentik proxy outpost (reverse-proxy mode) at the gateway; no request reaches the backend without a valid Authentik session + group membership |

## Why Authentik over Keycloak

Both were the candidates carried in `plan.md`/`docs/roadmap.md`. Authentik wins for
this platform:

1. **Built-in proxy/forward-auth outpost.** Roughly half the platform UIs do not
   speak OIDC (Prometheus, Alertmanager, Rollouts, Uptime, Hubble). Authentik
   secures them natively with its embedded outpost. Keycloak would require a
   separate `oauth2-proxy` deployment to achieve the same — more moving parts.
2. **Lighter footprint.** Authentik (Python) is lighter than Keycloak (Java/JVM),
   which matters on the single-node Phase 0 management cluster.
3. **GitOps-native config.** Authentik **blueprints** are declarative YAML applied
   on startup, so providers, applications, groups, and outposts live in git and
   reconcile automatically — consistent with the ArgoCD-everything model.
4. **Full IdP feature set.** Native OIDC + SAML + LDAP, per-application access
   policies, group RBAC, MFA — room to grow toward the multi-user, fine-grained
   access the platform requires.

Keycloak remains the better choice only at large-enterprise scale; Authentik can be
migrated from later if that ever becomes the case.

## Architecture

```text
                        ┌─────────────────────────────┐
  auth.platform ───────▶│ Authentik (server + worker) │
                        │  ├─ OIDC provider           │◀── ArgoCD / Grafana (OIDC)
                        │  └─ embedded proxy outpost  │◀── Prometheus / Alertmanager /
                        └──────────────┬──────────────┘     Rollouts / Gatus / Hubble /
                                       │                     Thanos / Pyroscope
                                       │                     (forward-auth, reverse-proxy)
                        ┌──────────────┴──────────────┐
                        │ CloudNativePG (PostgreSQL)  │   data layer
                        │ Valkey (Redis-compatible)   │
                        └─────────────────────────────┘
```

### Data layer

- **PostgreSQL via CloudNativePG (CNPG).** Operator-managed, declarative `Cluster`
  CR, images on `ghcr.io` (approved registry), runs non-root. Production-grade and
  backup-ready (integrates with the object-storage/Velero story); starts as a
  single instance on `local-path` and scales to HA when NUC nodes arrive.
- **Valkey** (BSD-licensed Redis fork) for Authentik's cache + Celery broker.

### Platform constraints honored

- **Kyverno (enforce):** all images come from approved registries (`ghcr.io`,
  `quay.io`); every pod sets resource requests, `runAsNonRoot`, `seccompProfile`,
  and drops all capabilities.
- **Talos + local-path:** non-root writes work as long as volumes are **not**
  mounted via `subPath` (verified). The data layer avoids subPath, so it runs
  non-root (unlike Prometheus/etcd which need root due to subPath chart mounts).

## Consequences

- Per-app basic auth is removed (it was non-functional anyway — see the monitoring
  values history). Authentik is the only auth path going forward.
- Adding a new app to SSO is a blueprint change (OIDC provider for OIDC-native
  apps, or a proxy provider + outpost route for the rest) — no bespoke per-app
  auth plumbing.
- Onboarding a user: create them in Authentik and assign groups
  (`platform-admins`, `platform-viewers`, …). See
  `docs/runbooks/sso-authentik.md`.

## Secrets

Generated once and stored in 1Password (NQLabs vault), consumed via ExternalSecrets:

- `authentik` — `secret_key`, `bootstrap_password`, `bootstrap_token`
- `authentik-postgres` — `password`
- `argocd-oidc` — `client_secret`
- `grafana-oidc` — `client_secret`
- `gatus-oidc` — `client_secret`
