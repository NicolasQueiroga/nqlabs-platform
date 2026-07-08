# Redpanda (Removed)

Redpanda was removed from the management cluster on 2026-07-08 (idle service).

## To re-add

1. Re-create the ArgoCD Application at `clusters/nqlabs-management/argocd/apps/redpanda.yaml`
2. Re-add these shared-file references:
   - `infrastructure/identity/authentik/blueprints/30-proxy.yaml` — redpanda provider + app + bindings
   - `infrastructure/identity/authentik/manifests/network-policies.yaml` — egress to redpanda:8080
   - `infrastructure/identity/authentik/manifests/referencegrant.yaml` — from namespace: redpanda
   - `infrastructure/monitoring/gatus/configmap.yaml` — Redpanda health endpoint
   - `infrastructure/monitoring/security-rules.yaml` — redpanda alert group
   - `infrastructure/monitoring/community-dashboards.yaml` — 3 Redpanda dashboards
   - `infrastructure/security/kyverno/policies/baseline.yaml` — redpanda in namespace exclusions + docker.redpanda.com in registry allowlist
   - `clusters/nqlabs-management/argocd/apps/projects.yaml` — https://charts.redpanda.com in sourceRepos
   - `infrastructure/networking/gateway/platform-gateway.yaml` — redpanda namespace in gateway-access labels
3. Add `https://charts.redpanda.com` Helm repo to ArgoCD
4. Sync the app and wait for Redpanda to be healthy

## What's still in this directory

All manifests are preserved: values.yaml, namespace, network-policies, observability, gatus-check, kyverno-exception.
