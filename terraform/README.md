# Terraform

> **Deprecated/stale:** prefer the platform `Create application` workflow for scaffolding (it generates app.yaml + environments). This Terraform predates the app.yaml split, named cluster destinations, and the plain-`<service>` namespace model, so it needs updating before reuse.


Terraform is used for platform onboarding contracts, not for directly mutating the
Kubernetes cluster.

Current purpose:

```text
service/product definition
  → generated apps/<service>/environments/*.yaml
  → pull request
  → ArgoCD ApplicationSet
  → ArgoCD sync
```

This keeps Git as the source of truth while allowing services/products to be defined
through a higher-level interface.

## Current modules

| Module | Purpose |
|--------|---------|
| `modules/nqlabs-service` | Generate service environment files consumed by the service ApplicationSet |

## Current service definitions

| Definition | Purpose |
|------------|---------|
| `services/demo` | Demo service staging/production environment files |

## State

Local Terraform state is ignored by `.gitignore`. Do not commit state files or
`.tfvars` files.

Provider lock files (`.terraform.lock.hcl`) are committed so repeated OpenTofu /
Terraform runs use the same provider selections. A remote state backend can be added
later when Terraform use becomes shared/team-operated.

## Operating model

Terraform writes files. It does not bypass GitOps.

```text
terraform apply
  → local file changes
  → git diff review
  → pull request
  → merge
  → ArgoCD reconciliation
```

Boundary: Terraform/OpenTofu is a scaffolder for service/product onboarding. It
should not become the owner of every runtime image update. Normal releases should
continue to update `apps/<service>/environments/*.yaml` by pull request, generated
from CI/release automation, so Git remains the single deployment source of truth.

## Isolation model

The `nqlabs-service` module can emit values for ResourceQuota, LimitRange, RBAC, and
CiliumNetworkPolicy resources rendered by `charts/nqlabs-service`.

These are namespace-scoped guardrails. They become truly per-service when a service
uses a dedicated namespace such as `<service>-staging` or `<service>-production` in
the current Mac lab.

The final NUC target is stronger: separate `nqlabs-staging` and `nqlabs-production`
clusters can use the same service namespace name, e.g. `namespace/payment`, because
the cluster boundary separates environments.
